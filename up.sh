#!/usr/bin/env bash
# =============================================================================
# up.sh — VM 생성부터 K3s 클러스터 구성, 완료 확인까지 한 번에 실행
#
# 순서:
#   1. 사전 검사  : 필요한 도구, provider, 설정 파일
#   2. VM 생성    : vagrant up (이미 떠 있으면 그대로 둔다)
#   3. SSH 확인   : ansible ping (VM 부팅 직후 대비 재시도)
#   4. 클러스터   : ansible-playbook site.yml
#   5. 완료 확인  : 맥에서 kubeconfig 로 노드 수/Ready, 시스템 파드, 웹 UI 응답 확인
#
# 사용: ./up.sh
# 재실행: 안전 (Vagrant/Ansible 모두 이미 된 단계는 건너뛴다)
# provider: ansible/group_vars/all.yml 의 vagrant_provider 를 따른다
# vagrant destroy -f  : VM 삭제 (다시 up.sh 실행하면 새로 생성)
# vagrant halt -f     : VM 종료 (다시 up.sh 실행하면 그대로 재사용)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ANSIBLE_DIR="$ROOT/ansible"
VARS="$ANSIBLE_DIR/group_vars/all.yml"
KUBECONFIG_PATH="$ROOT/kubeconfig"
TOKEN_PATH="$ROOT/headlamp-token.txt"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

# all.yml 의 단순 "key: value" 값 읽기 (주석 제거)
var() { awk -v k="$1:" '$1==k {sub(/#.*/,""); gsub(/[" ]/,"",$2); print $2}' "$VARS"; }

START=$(date +%s)

# ---------- 1. 사전 검사 ----------
step "1/5 사전 검사"
for c in vagrant ansible ansible-playbook kubectl curl; do
  command -v "$c" >/dev/null || fail "$c 가 없다 (brew install $c 등으로 설치)"
done
ok "도구: vagrant, ansible, kubectl, curl"

[ -f "$ROOT/Vagrantfile" ] && [ -f "$ANSIBLE_DIR/site.yml" ] && [ -f "$VARS" ] || fail "Vagrantfile / ansible 설정 파일이 없다"
ok "설정 파일"

PROVIDER="$(var vagrant_provider)"; PROVIDER="${PROVIDER:-virtualbox}"
case "$PROVIDER" in
  virtualbox)     command -v VBoxManage >/dev/null || fail "VirtualBox 가 없다" ;;
  vmware_desktop) vagrant plugin list | grep -q vagrant-vmware-desktop || fail "vagrant-vmware-desktop 플러그인이 없다" ;;
  *)              fail "지원하지 않는 provider: $PROVIDER" ;;
esac
ok "provider: $PROVIDER"

EXPECTED_NODES=$(grep -c 'ansible_host=' "$ANSIBLE_DIR/inventory.ini")
ok "인벤토리 노드 수: $EXPECTED_NODES"

# ---------- 2. VM 생성 ----------
step "2/5 VM 생성 (vagrant up)"
cd "$ROOT"
vagrant up --provider="$PROVIDER"
RUNNING=$(vagrant status --machine-readable | awk -F, '$3=="state" && $4=="running"' | wc -l | tr -d ' ')
[ "$RUNNING" -eq "$EXPECTED_NODES" ] || fail "실행 중 VM $RUNNING/$EXPECTED_NODES (vagrant status 확인)"
ok "VM $RUNNING 대 실행 중"

# ---------- 3. SSH 확인 ----------
step "3/5 Ansible 접속 확인"
cd "$ANSIBLE_DIR"
for i in $(seq 1 10); do
  ansible all -m ping -o >/dev/null 2>&1 && break
  [ "$i" -eq 10 ] && { ansible all -m ping -o || true; fail "SSH 접속 실패"; }
  sleep 5
done
ok "모든 노드 SSH 접속 가능"

# ---------- 4. 클러스터 구성 ----------
step "4/5 클러스터 구성 (ansible-playbook site.yml)"
ansible-playbook site.yml
ok "플레이북 완료"

# ---------- 5. 완료 확인 (맥에서 직접) ----------
step "5/5 완료 확인"
[ -s "$KUBECONFIG_PATH" ] || fail "kubeconfig 가 생성되지 않았다: $KUBECONFIG_PATH"
export KUBECONFIG="$KUBECONFIG_PATH"

kubectl get --raw /readyz >/dev/null || fail "API 서버 응답 없음"
ok "API 서버 응답 (맥 -> $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'))"

NODES=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
[ "$NODES" -eq "$EXPECTED_NODES" ] || fail "노드 $NODES/$EXPECTED_NODES 개만 조인됨"
kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null || fail "Ready 아닌 노드가 있다"
ok "노드 $NODES/$EXPECTED_NODES Ready"

kubectl -n kube-system wait --for=condition=Available deployment --all --timeout=180s >/dev/null \
  || fail "kube-system 디플로이먼트가 준비되지 않았다 (kubectl -n kube-system get pods)"
ok "kube-system (coredns, metrics-server 등) 정상"

UI_LINE=""
if [ "$(var install_dashboard)" = "true" ]; then
  MASTER_IP=$(awk '/^\[servers\]/{f=1;next} f && /ansible_host=/{sub(/.*ansible_host=/,""); print $1; exit}' "$ANSIBLE_DIR/inventory.ini")
  UI_URL="http://$MASTER_IP:$(var headlamp_node_port)"
  curl -fs -o /dev/null --max-time 5 "$UI_URL" || fail "Headlamp 응답 없음: $UI_URL"
  [ -s "$TOKEN_PATH" ] || fail "Headlamp 토큰 파일 없음: $TOKEN_PATH"
  ok "Headlamp 응답: $UI_URL"
  UI_LINE="  웹 UI      : $UI_URL  (토큰: headlamp-token.txt)"
fi

# ---------- 결과 ----------
echo
kubectl get nodes -o wide
printf '\n\033[1;32m클러스터 준비 완료 (%ss)\033[0m\n' "$(( $(date +%s) - START ))"
echo "  kubeconfig: export KUBECONFIG=$KUBECONFIG_PATH"
[ -n "$UI_LINE" ] && echo "$UI_LINE"
echo "  종료/삭제 : vagrant halt / vagrant destroy -f"
