# launch, doctor, drive, cleanup이 함께 쓰는 값. RUN_ID가 한 번의 검증 실행을 가리킨다.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
VARS="$ROOT/ansible/group_vars/all.yml"
export KUBECONFIG="$ROOT/kubeconfig"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"
EVIDENCE_BASE="$ROOT/verify-results"
MANAGED_BY=verify-k3s-lab

var() { awk -v k="$1:" '$1==k {sub(/#.*/,""); gsub(/[" ]/,"",$2); print $2}' "$VARS"; }
MASTER_IP=$(awk '/^\[servers\]/{f=1;next} f && /ansible_host=/{sub(/.*ansible_host=/,""); print $1; exit}' "$ROOT/ansible/inventory.ini")
EXPECTED_NODES=$(grep -c 'ansible_host=' "$ROOT/ansible/inventory.ini")
REGISTRY="$MASTER_IP:$(var registry_node_port)"
GRAFANA="http://$MASTER_IP:$(var grafana_node_port)"
PROMETHEUS="http://$MASTER_IP:$(var prometheus_node_port)"
ALERTMANAGER="http://$MASTER_IP:$(var alertmanager_node_port)"
HEADLAMP="http://$MASTER_IP:$(var headlamp_node_port)"

need_run_id() {
  [ -n "${RUN_ID:-}" ] || { echo "RUN_ID가 필요하다. launch.sh가 출력한 값을 export RUN_ID=... 로 넣는다" >&2; exit 2; }
  NS="verify-k3s-$RUN_ID"
  EVIDENCE="$EVIDENCE_BASE/$RUN_ID"
}
