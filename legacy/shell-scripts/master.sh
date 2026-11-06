#!/usr/bin/env bash
# =============================================================================
# master.sh — ControlPlane 구성 (프로비저닝 2단계)
#
# 목적: K3s server 를 설치해 클러스터의 컨트롤 플레인(API 서버)을 띄운다.
# 역할:
#   - NODE_IP 가 붙은 NIC 를 찾아 flannel 이 그 NIC 를 쓰도록 지정
#     (Vagrant NAT NIC 로 잘못 잡히는 문제 방지)
#   - K3s server 설치 후 노드가 Ready 될 때까지 대기
#   - VM 안 vagrant 사용자용 kubectl 설정 (kubeconfig, alias k)
#   - 호스트(맥)용 kubeconfig 를 /vagrant/kubeconfig 로 내보냄
# 실행 위치: controlplane 노드만 (common.sh 다음, worker.sh 보다 먼저)
# 환경변수: NODE_IP, K3S_TOKEN, K3S_VERSION
# 재실행: 안전 (k3s 가 이미 실행 중이면 설치 생략)
# =============================================================================
set -euo pipefail

# NODE_IP가 붙어 있는 NIC 이름을 자동으로 찾는다 (eth1, ens160, enp0s8 등 무엇이든)
IFACE="$(ip -o -4 addr show | awk -v ip="$NODE_IP" '{split($4,a,"/"); if (a[1]==ip) print $2}')"
if [ -z "$IFACE" ]; then
  echo "[master] $NODE_IP 가 할당된 인터페이스를 찾지 못했다"; ip -o -4 addr show; exit 1
fi
echo "[master] node-ip=$NODE_IP, flannel-iface=$IFACE"

if ! systemctl is-active --quiet k3s; then
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="$K3S_VERSION" K3S_TOKEN="$K3S_TOKEN" sh -s - server \
      --node-ip="$NODE_IP" \
      --advertise-address="$NODE_IP" \
      --tls-san="$NODE_IP" \
      --flannel-iface="$IFACE" \
      --write-kubeconfig-mode=644
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "[master] API 서버 준비 대기"
for i in $(seq 1 60); do
  kubectl get nodes >/dev/null 2>&1 && break
  sleep 3
done
kubectl wait --for=condition=Ready "node/$(hostname)" --timeout=180s

# vagrant 사용자가 VM 안에서 바로 kubectl 쓰도록
mkdir -p /home/vagrant/.kube
cp "$KUBECONFIG" /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
grep -q "alias k=" /home/vagrant/.bashrc || cat >> /home/vagrant/.bashrc <<'EOF'
alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
EOF

# 호스트(맥)에서 쓸 kubeconfig: 주소를 127.0.0.1 → 마스터 IP로 바꿔 공유 폴더에 저장
sed "s/127.0.0.1/$NODE_IP/" "$KUBECONFIG" > /vagrant/kubeconfig
echo "[master] 호스트용 kubeconfig 저장: 프로젝트 폴더/kubeconfig"

echo "[master] 완료"
kubectl get nodes -o wide
