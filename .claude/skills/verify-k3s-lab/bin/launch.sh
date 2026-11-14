#!/usr/bin/env bash
# 클러스터가 꺼져 있을 때만 up.sh로 띄우고, 이 실행 전용 namespace를 만든다. 마지막 줄이 RUN_ID다.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

running=$(cd "$ROOT" && vagrant status --machine-readable | awk -F, '$3=="state" && $4=="running"' | wc -l | tr -d ' ')
if [ "$running" = 0 ]; then
  echo "VM이 모두 꺼져 있다. up.sh로 띄운다"
  "$ROOT/up.sh"
elif ! "$SKILL_DIR/bin/doctor.sh" >/dev/null; then
  if [ "${VERIFY_ALLOW_UP:-0}" = 1 ]; then
    echo "VM $running/$EXPECTED_NODES 대가 떠 있지만 doctor가 실패했다. VERIFY_ALLOW_UP=1 이라 up.sh를 다시 적용한다"
    "$ROOT/up.sh"
  else
    "$SKILL_DIR/bin/doctor.sh" || true
    echo "VM $running/$EXPECTED_NODES 대가 떠 있지만 doctor가 실패했다. 다른 세션이 쓰는 중일 수 있어 up.sh를 돌리지 않는다" >&2
    echo "운영자가 허락하면 VERIFY_ALLOW_UP=1 로 다시 실행한다" >&2
    exit 1
  fi
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)"
need_run_id
mkdir -p "$EVIDENCE"
kubectl create namespace "$NS" --dry-run=client -o yaml \
  | kubectl label --local -f - "app.kubernetes.io/managed-by=$MANAGED_BY" -o yaml \
  | kubectl apply -f - >/dev/null
RUN_ID=$RUN_ID "$SKILL_DIR/bin/doctor.sh" | tee "$EVIDENCE/doctor.txt"
echo "ready"
echo "RUN_ID=$RUN_ID"
