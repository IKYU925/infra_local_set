#!/usr/bin/env bash
# =============================================================================
# worker.sh — Worker 노드 조인 (프로비저닝 3단계)
#
# 목적: K3s agent 를 설치해 이 노드를 기존 클러스터에 워커로 붙인다.
# 역할:
#   - NODE_IP 가 붙은 NIC 를 찾아 flannel 인터페이스로 지정
#   - 마스터 API(6443)가 응답할 때까지 대기 (마스터보다 먼저 뜬 경우 대비)
#   - K3S_URL + K3S_TOKEN 으로 agent 설치 → 클러스터 조인
# 실행 위치: 각 worker 노드 (common.sh 다음, master.sh 완료 이후)
# 환경변수: NODE_IP, MASTER_IP, K3S_TOKEN, K3S_VERSION
# 재실행: 안전 (k3s-agent 가 이미 실행 중이면 설치 생략)
# =============================================================================
set -euo pipefail

IFACE="$(ip -o -4 addr show | awk -v ip="$NODE_IP" '{split($4,a,"/"); if (a[1]==ip) print $2}')"
if [ -z "$IFACE" ]; then
  echo "[worker] $NODE_IP 가 할당된 인터페이스를 찾지 못했다"; ip -o -4 addr show; exit 1
fi
echo "[worker] node-ip=$NODE_IP, flannel-iface=$IFACE, master=$MASTER_IP"

# 마스터 API(6443)가 응답할 때까지 대기 (최대 약 5분)
echo "[worker] 마스터 응답 대기"
for i in $(seq 1 100); do
  if curl -sk --max-time 3 "https://${MASTER_IP}:6443/ping" | grep -q pong; then
    echo "[worker] 마스터 응답 확인"; break
  fi
  if [ "$i" -eq 100 ]; then
    echo "[worker] 마스터에 연결하지 못했다. controlplane 상태를 먼저 확인할 것"; exit 1
  fi
  sleep 3
done

if ! systemctl is-active --quiet k3s-agent; then
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="$K3S_VERSION" \
    K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="$K3S_TOKEN" sh -s - agent \
      --node-ip="$NODE_IP" \
      --flannel-iface="$IFACE"
fi

echo "[worker] 완료 (조인 상태는 controlplane 에서 kubectl get nodes 로 확인)"
