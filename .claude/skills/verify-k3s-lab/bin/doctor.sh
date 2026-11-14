#!/usr/bin/env bash
# 읽기만 하는 점검. 이 클러스터를 검증에 써도 되는지 답한다. RUN_ID가 있으면 검증용 namespace도 본다.
set -uo pipefail
source "$(dirname "$0")/_env.sh"
ok=1
check() { if eval "$2" >/dev/null 2>&1; then echo "OK   $1"; else echo "FAIL $1"; ok=0; fi; }
check "kubeconfig 있음($KUBECONFIG)" '[ -s "$KUBECONFIG" ]'
check "맥에서 API 서버 응답(/readyz, 막히면 iTerm 로컬 네트워크 권한)" 'kubectl get --raw /readyz'
check "노드 ${EXPECTED_NODES}개 모두 Ready" '[ "$(kubectl get nodes --no-headers | awk "\$2==\"Ready\"" | wc -l | tr -d " ")" = "$EXPECTED_NODES" ]'
check "배치 라벨(k3s-w1 workload=app, k3s-w2 workload=monitoring)" '[ "$(kubectl get node k3s-w1 -o jsonpath="{.metadata.labels.workload}")" = app ] && [ "$(kubectl get node k3s-w2 -o jsonpath="{.metadata.labels.workload}")" = monitoring ]'
check "kube-system 디플로이먼트 Available" 'kubectl -n kube-system wait --for=condition=Available deployment --all --timeout=5s'
check "레지스트리 응답($REGISTRY/v2/)" 'curl -fs -m5 http://$REGISTRY/v2/'
check "Grafana 응답($GRAFANA/api/health)" 'curl -fs -m5 $GRAFANA/api/health'
check "Prometheus 준비($PROMETHEUS/-/ready)" 'curl -fs -m5 $PROMETHEUS/-/ready'
check "Alertmanager 준비($ALERTMANAGER/-/ready)" 'curl -fs -m5 $ALERTMANAGER/-/ready'
check "Headlamp 응답($HEADLAMP)" 'curl -fs -m5 -o /dev/null $HEADLAMP'
check "인증 파일(grafana-admin-password.txt, headlamp-token.txt)" '[ -s "$ROOT/grafana-admin-password.txt" ] && [ -s "$ROOT/headlamp-token.txt" ]'
if [ -n "${RUN_ID:-}" ]; then
  need_run_id
  check "검증 namespace $NS 가 이 스킬 소유" '[ "$(kubectl get ns $NS -o jsonpath="{.metadata.labels.app\.kubernetes\.io/managed-by}")" = $MANAGED_BY ]'
fi
[ $ok = 1 ] && echo "doctor: 이 클러스터로 검증해도 된다" || { echo "doctor: 문제가 있다. SKILL.md 의 Launch 판단표를 본다"; exit 1; }
