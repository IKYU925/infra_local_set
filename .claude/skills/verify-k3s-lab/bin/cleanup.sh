#!/usr/bin/env bash
# 이 실행이 만든 namespace와 레지스트리 태그만 지운다. VM, 클러스터, 다른 namespace, 증거(verify-results/<RUN_ID>)는 그대로 둔다.
set -euo pipefail
source "$(dirname "$0")/_env.sh"
need_run_id
owner=$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || true)
if [ "$owner" = "$MANAGED_BY" ]; then
  kubectl delete namespace "$NS" --wait=true --timeout=120s >/dev/null
elif [ -n "$owner" ]; then
  echo "$NS 는 이 스킬이 만든 namespace가 아니다(managed-by=$owner). 지우지 않는다" >&2; exit 1
fi
if [ -f "$EVIDENCE/registry.env" ]; then
  source "$EVIDENCE/registry.env"
  [ -n "${REGISTRY_DIGEST:-}" ] && curl -fs -X DELETE "http://$REGISTRY/v2/verify-k3s/busybox/manifests/$REGISTRY_DIGEST" -o /dev/null || true
  docker rmi "$REGISTRY/verify-k3s/busybox:$RUN_ID" >/dev/null 2>&1 || true
fi
echo "cleaned $NS, evidence kept at $EVIDENCE"
