# k3s-vagrant-lab

Vagrant + Ansible + K3s 로 로컬에 3노드 쿠버네티스 클러스터(ControlPlane 1, Worker 2)를 만드는 실습 환경이다.

### 역할 분리

| 도구 | 담당 | 실행 |
|---|---|---|
| Vagrant | VM 생성 (CPU, 메모리, 네트워크) | `vagrant up` |
| Ansible | 클러스터 구성 (공통 설정, K3s server/agent, 웹 UI) | `ansible-playbook site.yml` |

인프라(VM)와 구성(소프트웨어 설치)을 나누면, VM 은 그대로 두고 구성만 여러 번 다시 적용할 수 있다.

### 노드

| 노드 | 역할 | IP |
|---|---|---|
| controlplane | K3s server | 192.168.56.10 |
| node01 | K3s agent | 192.168.56.11 |
| node02 | K3s agent | 192.168.56.12 |

### 파일 구조

```
k3s-vagrant-lab/
├── Vagrantfile                  # VM 3대 정의 (프로비저닝 없음)
├── ansible/
│   ├── ansible.cfg              # 인벤토리 경로, SSH 옵션
│   ├── inventory.ini            # 호스트 목록과 그룹 (servers, agents)
│   ├── group_vars/all.yml       # 공통 변수 (SSH 키 경로, 토큰, 버전)
│   ├── site.yml                 # 플레이 실행 순서
│   └── roles/
│       ├── common/              # 시간대, /etc/hosts, NIC 탐지
│       ├── k3s_server/          # K3s server 설치, kubeconfig 생성
│       ├── k3s_agent/           # 마스터 대기 후 조인
│       └── headlamp/            # (선택) 웹 UI Headlamp + 토큰
└── legacy/                      # 사용하지 않는 이전 버전 (비교용)
    └── shell-scripts/           # 셸 프로비저닝 버전
```

실행이 끝나면 프로젝트 폴더에 `kubeconfig`, `headlamp-token.txt`, `.k3s-token` 이 생긴다.
인증 정보가 담긴 파일이라 `.gitignore` 로 git 에서 제외한다 (`.vagrant/` 의 SSH 개인키도 마찬가지).

### 실행 순서

한 번에 실행 (사전 검사 → VM 생성 → 클러스터 구성 → 완료 확인):

```bash
./up.sh
```

단계별로 실행:

```bash
# 1. VM 생성
vagrant up

# 2. 접속 확인
cd ansible
ansible all -m ping

# 3. 클러스터 구성
ansible-playbook site.yml

# 4. 맥에서 확인
cd ..
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes -o wide
```

### 자주 쓰는 명령

```bash
ansible-playbook site.yml --limit node01          # 특정 노드만 다시 적용
ansible-playbook site.yml --check                 # 바뀔 내용만 미리 보기
ansible-playbook site.yml --tags dashboard        # 웹 UI 단계만 실행 (태그: common, server, agent, dashboard, status)
vagrant snapshot save clean                       # 정상 상태 저장
vagrant snapshot restore clean                    # 복구
vagrant halt                                      # 종료
vagrant destroy -f                                # 전체 삭제
```

### 웹 UI (Headlamp) 접속

브라우저에서 `http://192.168.56.10:30003` 접속 후 `headlamp-token.txt` 내용을 토큰으로 입력한다.
NodePort 라서 port-forward 없이 아무 노드 IP 로 접속할 수 있다.

Kubernetes Dashboard 는 2026-01 아카이브되었고 Helm 저장소도 404 로 내려가서 Headlamp 로 교체했다.
