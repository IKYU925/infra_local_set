#!/usr/bin/env bash
# 기능 이름을 받아 사용자 경로로 확인하고 증거를 남긴다. 인자가 없으면 Docker가 필요 없는 기능을 모두 돈다.
# 사용: RUN_ID=... drive.sh [placement|logs|metrics|alerts|headlamp|registry ...]
set -uo pipefail
source "$(dirname "$0")/_env.sh"
need_run_id
mkdir -p "$EVIDENCE"
PY=/usr/bin/python3
GRAFANA_AUTH="admin:$(cat "$ROOT/grafana-admin-password.txt")"
failed=0

log()  { echo "[$1] $2" | tee -a "$EVIDENCE/drive.log"; }
pass() { log "$1" "PASS $2"; }
fail() { log "$1" "FAIL $2"; failed=1; }

# 검증용 Pod. 표지 문자열을 한 번 찍고 대기한다. 리소스는 다른 세션의 앱을 밀어내지 않게 작게 잡는다.
probe_pod() {
  local name=$1 workload=$2 image=$3 marker=$4
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $NS
  labels: {app.kubernetes.io/name: $name, app.kubernetes.io/managed-by: $MANAGED_BY}
spec:
  nodeSelector: {workload: $workload}
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
  containers:
    - name: probe
      image: $image
      imagePullPolicy: Always
      command: ["sh", "-c", "echo $marker; sleep 3600"]
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {memory: 32Mi}
EOF
  kubectl -n "$NS" wait --for=condition=Ready "pod/$name" --timeout=180s >/dev/null
}

poll() {
  local tries=$1; shift
  for _ in $(seq 1 "$tries"); do "$@" && return 0; sleep 5; done
  return 1
}

drive_placement() {
  local f=placement
  for pair in app:k3s-w1 monitoring:k3s-w2; do
    local workload=${pair%%:*} want=${pair##*:} pod="placement-${pair%%:*}"
    if ! probe_pod "$pod" "$workload" busybox:1.36 "verify-k3s-$RUN_ID-$pod"; then
      fail $f "$pod 이 Ready가 되지 않음"; kubectl -n "$NS" describe pod "$pod" > "$EVIDENCE/$pod.describe.txt"; continue
    fi
    kubectl -n "$NS" get pod "$pod" -o wide > "$EVIDENCE/$pod.txt"
    local got; got=$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.spec.nodeName}')
    [ "$got" = "$want" ] && pass $f "workload=$workload Pod가 $got 에 배치" || fail $f "workload=$workload Pod가 $got 에 배치(기대 $want)"
  done
}

drive_logs() {
  local f=logs marker="verify-k3s-$RUN_ID-logs"
  probe_pod logs-probe app busybox:1.36 "$marker" || { fail $f "logs-probe 가 Ready가 되지 않음"; return; }
  local q="{namespace=\"$NS\"} |= \"$marker\""
  loki_has_marker() {
    curl -s -u "$GRAFANA_AUTH" -G "$GRAFANA/api/datasources/proxy/uid/loki/loki/api/v1/query_range" \
      --data-urlencode "query=$q" --data-urlencode "since=15m" > "$EVIDENCE/logs.loki.json"
    $PY -c 'import json,sys;r=json.load(open(sys.argv[1]))["data"]["result"];sys.exit(0 if r else 1)' "$EVIDENCE/logs.loki.json"
  }
  if poll 24 loki_has_marker; then
    pass $f "Grafana의 Loki 데이터소스에서 표지 '$marker' 조회됨(Alloy 수집 경로)"
  else
    fail $f "2분 안에 Loki에서 표지를 찾지 못함. 마지막 응답은 logs.loki.json"
  fi
}

drive_metrics() {
  local f=metrics
  probe_pod metrics-probe app busybox:1.36 "verify-k3s-$RUN_ID-metrics" || { fail $f "metrics-probe 가 Ready가 되지 않음"; return; }
  prom_has_pod() {
    curl -s -G "$PROMETHEUS/api/v1/query" --data-urlencode "query=kube_pod_info{namespace=\"$NS\",pod=\"metrics-probe\"}" > "$EVIDENCE/metrics.kube_pod_info.json"
    $PY -c 'import json,sys;r=json.load(open(sys.argv[1]))["data"]["result"];sys.exit(0 if r and r[0]["metric"].get("node")=="k3s-w1" else 1)' "$EVIDENCE/metrics.kube_pod_info.json"
  }
  if poll 24 prom_has_pod; then
    pass $f "Prometheus의 kube_pod_info에 metrics-probe(node=k3s-w1)가 잡힘"
  else
    fail $f "2분 안에 Prometheus에서 metrics-probe를 찾지 못함. 마지막 응답은 metrics.kube_pod_info.json"
  fi
  curl -s "$PROMETHEUS/api/v1/targets?state=active" > "$EVIDENCE/metrics.targets.json"
  local down; down=$($PY -c 'import json,sys;t=json.load(open(sys.argv[1]))["data"]["activeTargets"];print(sorted({x["labels"].get("job","?") for x in t if x["health"]!="up"}))' "$EVIDENCE/metrics.targets.json")
  log $f "INFO down 상태 수집 대상 job: $down"
}

drive_alerts() {
  local f=alerts
  curl -s "$ALERTMANAGER/api/v2/status" > "$EVIDENCE/alerts.status.json"
  # 상태 API는 웹훅 URL을 <secret>으로 가리므로, URL은 operator가 만든 설정 Secret에서 읽는다
  kubectl -n "$(var monitoring_namespace)" get secret alertmanager-kube-prometheus-stack-alertmanager-generated \
    -o jsonpath='{.data.alertmanager\.yaml\.gz}' | base64 -d | gunzip | grep -E '^\s*url:' | grep -v '<secret>' > "$EVIDENCE/alerts.webhook-urls.txt"
  $PY - "$EVIDENCE/alerts.status.json" "$NS" "$(var ai_automation_webhook_url)" "$EVIDENCE/alerts.webhook-urls.txt" <<'EOF' | tee -a "$EVIDENCE/drive.log"
import json, re, sys
cfg = json.load(open(sys.argv[1]))["config"]["original"]
ns, url = sys.argv[2], sys.argv[3]
urls = open(sys.argv[4]).read()
m = re.search(r'namespace\s*=~\s*"?([^"\n]+)"?', cfg)
checks = [
    ("ai-automation receiver가 웹훅 " + url + " 로 등록", "name: ai-automation" in cfg and url in urls),
    ("앱 namespace 매처 " + (m.group(1) if m else "?") + " 가 ai-automation 으로 라우팅", bool(m)),
    ("노드 장애(KubeNodeNotReady) 라우팅", "KubeNodeNotReady" in cfg),
    ("검증 namespace " + ns + " 는 매처에 걸리지 않음(자동화로 알림이 가지 않음)", bool(m) and not re.fullmatch(m.group(1), ns)),
]
bad = 0
for name, ok in checks:
    print(f"[alerts] {'PASS' if ok else 'FAIL'} {name}")
    bad |= not ok
sys.exit(bad)
EOF
  [ "${PIPESTATUS[0]}" = 0 ] || failed=1
}

drive_headlamp() {
  local f=headlamp token server ca
  curl -s -m5 -o "$EVIDENCE/headlamp.index.html" -w '%{http_code}' "$HEADLAMP" | grep -qx 200 \
    && grep -qi headlamp "$EVIDENCE/headlamp.index.html" \
    && pass $f "웹 UI $HEADLAMP 가 200과 Headlamp 페이지를 돌려줌" || fail $f "웹 UI 응답 이상($HEADLAMP)"
  token=$(cat "$ROOT/headlamp-token.txt")
  server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  ca=$(mktemp); kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$ca"
  curl -s --cacert "$ca" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -X POST \
    "$server/apis/authentication.k8s.io/v1/selfsubjectreviews" \
    -d '{"apiVersion":"authentication.k8s.io/v1","kind":"SelfSubjectReview"}' > "$EVIDENCE/headlamp.whoami.json"
  curl -s --cacert "$ca" -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -X POST \
    "$server/apis/authorization.k8s.io/v1/selfsubjectaccessreviews" \
    -d '{"apiVersion":"authorization.k8s.io/v1","kind":"SelfSubjectAccessReview","spec":{"resourceAttributes":{"verb":"list","resource":"pods"}}}' > "$EVIDENCE/headlamp.can-i.json"
  rm -f "$ca"
  $PY -c 'import json,sys;u=json.load(open(sys.argv[1]))["status"]["userInfo"]["username"];a=json.load(open(sys.argv[2]))["status"]["allowed"];print(u);sys.exit(0 if u=="system:serviceaccount:headlamp:headlamp-admin" and a else 1)' \
    "$EVIDENCE/headlamp.whoami.json" "$EVIDENCE/headlamp.can-i.json" > "$EVIDENCE/headlamp.user.txt" 2>&1 \
    && pass $f "로그인 토큰이 headlamp-admin 으로 인증되고 전체 Pod 조회 권한이 있음" \
    || fail $f "로그인 토큰 인증 또는 권한 확인 실패(headlamp.whoami.json, headlamp.can-i.json)"
}

drive_registry() {
  local f=registry image="$REGISTRY/verify-k3s/busybox:$RUN_ID"
  if ! docker info >/dev/null 2>&1; then
    fail $f "Docker 데몬이 꺼져 있다. Docker Desktop을 켠 뒤 다시 실행한다"; return
  fi
  if ! docker info --format '{{json .RegistryConfig.IndexConfigs}}' | grep -q "\"$REGISTRY\""; then
    fail $f "맥 Docker의 insecure-registries에 $REGISTRY 가 없다(README 참고)"; return
  fi
  { docker pull busybox:1.36 && docker tag busybox:1.36 "$image" && docker push "$image"; } > "$EVIDENCE/registry.push.log" 2>&1 \
    || { fail $f "맥에서 push 실패(registry.push.log)"; return; }
  local digest
  digest=$(curl -sI -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' \
    "http://$REGISTRY/v2/verify-k3s/busybox/manifests/$RUN_ID" | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}' | tr -d '\r')
  echo "REGISTRY_DIGEST=$digest" > "$EVIDENCE/registry.env"
  curl -s "http://$REGISTRY/v2/verify-k3s/busybox/tags/list" > "$EVIDENCE/registry.tags.json"
  grep -q "\"$RUN_ID\"" "$EVIDENCE/registry.tags.json" && pass $f "맥에서 push 한 $image 가 태그 목록에 있음" || fail $f "태그 목록에 $RUN_ID 가 없음"
  if probe_pod registry-probe app "$image" "verify-k3s-$RUN_ID-registry"; then
    kubectl -n "$NS" get events --field-selector involvedObject.name=registry-probe > "$EVIDENCE/registry.events.txt"
    grep -q "Successfully pulled image \"$image\"" "$EVIDENCE/registry.events.txt" \
      && pass $f "k3s-w1 이 로컬 레지스트리에서 이미지를 받아 Pod를 띄움" || fail $f "pull 이벤트를 찾지 못함(registry.events.txt)"
  else
    fail $f "registry-probe 가 Ready가 되지 않음"; kubectl -n "$NS" describe pod registry-probe > "$EVIDENCE/registry-probe.describe.txt"
  fi
}

features=("$@")
[ ${#features[@]} = 0 ] && features=(placement logs metrics alerts headlamp)
for feat in "${features[@]}"; do
  declare -F "drive_$feat" >/dev/null || { fail "$feat" "알 수 없는 기능. placement logs metrics alerts headlamp registry 중에서 고른다"; continue; }
  "drive_$feat"
done
kubectl -n "$NS" get pods -o wide > "$EVIDENCE/pods.txt" 2>&1
[ $failed = 0 ] && echo "drive: 모두 PASS, 증거 $EVIDENCE" || { echo "drive: FAIL 있음, 증거 $EVIDENCE"; exit 1; }
