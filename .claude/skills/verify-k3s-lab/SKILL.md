---
name: verify-k3s-lab
description: infra_local_set(k3s-vagrant-lab)의 3노드 K3s 클러스터가 사용자가 쓰는 대로 동작하는지 맥에서 확인할 때 쓴다. 노드 배치 라벨, 로컬 레지스트리 push/pull, Alloy에서 Loki로 가는 Pod 로그, Prometheus 수집, Alertmanager에서 AI 자동화로 가는 알림 라우팅, Headlamp 웹 UI와 토큰을 실행마다 따로 만드는 namespace(verify-k3s-<RUN_ID>) 안에서 검증하고 증거를 남긴다. 다른 세션이 같은 클러스터를 쓰는 중이어도 VM과 다른 namespace는 건드리지 않는다. up.sh, Ansible 역할, Helm values를 바꾼 뒤나 클러스터가 이상해 보일 때 쓴다.
---

# verify-k3s-lab

이 레포가 만드는 것은 맥에서 쓰는 로컬 K3s 클러스터다. 사용자가 만지는 지점은 `./up.sh`, 맥의 `kubectl`(`kubeconfig`), 레지스트리(`192.168.56.10:30500`), Grafana(30030), Prometheus(30090), Alertmanager(30093), Headlamp(30003)다. 화면이 있는 것은 Grafana와 Headlamp인데, 이 스킬은 브라우저가 부르는 것과 같은 HTTP API로 확인한다.

모든 명령은 저장소 루트(`infra_local_set/`)에서 실행한다. 주소와 포트는 `ansible/inventory.ini`와 `ansible/group_vars/all.yml`에서 읽는다(`bin/_env.sh`).

## 격리 규칙

클러스터는 하나뿐이다. VM 이름과 IP(192.168.56.10~12)가 고정이라 두 번째 인스턴스를 띄울 수 없다. 그래서 다른 세션이 쓰는 클러스터를 그대로 공유하고, 다음을 지킨다.

- 검증이 만드는 것은 `verify-k3s-<RUN_ID>` namespace(라벨 `app.kubernetes.io/managed-by=verify-k3s-lab`)와 레지스트리 저장소 `verify-k3s/busybox`의 `<RUN_ID>` 태그뿐이다.
- 클러스터가 떠 있으면 `up.sh`, `ansible-playbook`, `vagrant halt/destroy/reload`를 돌리지 않는다. 플레이북은 레지스트리 설정이 바뀌면 K3s를 재시작하고 Helm 릴리스를 업그레이드한다.
- `shop`, `aiops`, `monitoring`, `registry`, `headlamp`, `kube-system`에는 쓰지 않는다. 읽기만 한다. `shop`과 `aiops`의 알림은 AI 자동화 웹훅으로 가므로, 거기서 Pod를 죽이거나 만들면 다른 세션의 파이프라인에 장애가 접수된다.
- 검증 Pod는 busybox에 요청 10m CPU, 16Mi 메모리로 작게 띄운다.

## Launch

```bash
.claude/skills/verify-k3s-lab/bin/launch.sh
export RUN_ID=<마지막 줄의 값>
```

`launch.sh`는 클러스터 상태에 따라 다음처럼 판단한다.

| VM 상태 | doctor | 하는 일 |
| --- | --- | --- |
| 모두 꺼짐(아무도 쓰지 않음) | 해당 없음 | `./up.sh`로 처음부터 띄운다. 박스 다운로드와 Helm 설치 때문에 수 분 이상 걸린다 |
| 떠 있음 | 통과 | 클러스터를 건드리지 않는다 |
| 떠 있음 | 실패 | 멈춘다. 운영자가 허락하면 `VERIFY_ALLOW_UP=1`로 다시 실행해 `up.sh`를 다시 적용한다 |

그다음 검증 namespace를 만들고 doctor를 한 번 더 돌린다. 출력 끝의 `ready`와 `RUN_ID=...`가 준비 완료 신호다. 쓸 수 있는 상태의 기준은 doctor의 모든 항목이 OK인 것이다. 프로세스가 응답하는 것만으로는 부족하다.

## Doctor

```bash
.claude/skills/verify-k3s-lab/bin/doctor.sh                 # 클러스터만
RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/doctor.sh  # 검증 namespace 소유까지
```

읽기만 한다. kubeconfig, 맥에서 API 서버 응답, 노드 수와 Ready, 배치 라벨, kube-system 디플로이먼트, 레지스트리, Grafana, Prometheus, Alertmanager, Headlamp 응답, 인증 파일, 검증 namespace의 소유 라벨을 확인한다. 하나라도 FAIL이면 drive하지 않는다. 무엇이든 이상해 보이면 먼저 실행한다.

맥에서 API 서버 확인만 `no route to host`로 실패하고 VM 안(`vagrant ssh k3s-cp -c 'sudo k3s kubectl get nodes'`)은 정상이면, 클러스터 문제가 아니라 macOS 로컬 네트워크 권한 문제다. 시스템 설정 → 개인정보 보호 및 보안 → 로컬 네트워크에서 터미널 앱(iTerm)을 켜고 터미널을 다시 시작한다. Apple이 서명한 `curl`과 `/usr/bin/python3`은 권한이 없어도 통과하고, Homebrew의 `kubectl`과 Ansible의 Python은 막힌다. 그래서 헬퍼의 JSON 처리는 `/usr/bin/python3`로 한다.

## Drive

```bash
RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh                 # placement logs metrics alerts headlamp
RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh registry        # Docker 필요
RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh placement logs  # 일부만
```

기능 이름마다 `[기능] PASS|FAIL 설명` 줄을 찍고, 하나라도 FAIL이면 종료 코드 1이다. 기능별 경로와 기대 결과는 [features/README.md](features/README.md)에 있다.

| 기능 | 사용자 경로 | 통과 기준 |
| --- | --- | --- |
| `placement` | `nodeSelector: {workload: app\|monitoring}` Pod | app은 k3s-w1, monitoring은 k3s-w2 |
| `logs` | Pod stdout → Alloy → Loki → Grafana Loki 데이터소스 | 표지 문자열이 2분 안에 조회됨 |
| `metrics` | kube-state-metrics → Prometheus `/api/v1/query` | `kube_pod_info`에 검증 Pod가 node=k3s-w1로 잡힘 |
| `alerts` | Alertmanager `/api/v2/status`, 설정 Secret | ai-automation 웹훅, `shop\|aiops` 매처, 노드 장애 라우팅, 검증 namespace 비해당 |
| `headlamp` | 웹 UI 200, `headlamp-token.txt` 토큰으로 API 인증 | 사용자 headlamp-admin, 전체 Pod 조회 허용 |
| `registry` | 맥 `docker push` → 노드 containerd pull | 태그 목록에 있음, Pod 이벤트에 로컬 레지스트리 pull 성공 |

## Evidence

증거는 `verify-results/<RUN_ID>/`에 남고 git에서 제외된다. cleanup 후에도 지우지 않는다.

- `doctor.txt`: launch 직후 doctor 결과
- `drive.log`: 기능별 PASS, FAIL, INFO 줄
- `placement-*.txt`, `pods.txt`: Pod와 배치된 노드
- `logs.loki.json`: Grafana를 거친 Loki 조회 응답(표지 문자열 포함)
- `metrics.kube_pod_info.json`, `metrics.targets.json`: Prometheus 응답과 수집 대상 상태
- `alerts.status.json`, `alerts.webhook-urls.txt`: Alertmanager 설정과 실제 웹훅 URL
- `headlamp.index.html`, `headlamp.whoami.json`, `headlamp.can-i.json`: 웹 UI 응답과 토큰 인증 결과
- `registry.push.log`, `registry.tags.json`, `registry.events.txt`, `registry.env`: push 로그, 태그 목록, pull 이벤트, 지울 digest

증명 기준은 다음과 같다.

- 실제 사용자 경로만 쓴다. 로그는 Pod가 stdout에 찍은 것을 Grafana에서 조회하고, Loki에 직접 push하지 않는다. 이미지는 맥에서 push하고 노드가 pull하게 하며, VM 안에서 `ctr import`하지 않는다.
- 행동과 결과를 함께 남긴다. Pod를 만든 기록(`pods.txt`)과 그 Pod가 관측 도구에 나타난 응답 JSON이 둘 다 있어야 한다.
- 부수 효과를 확인한다. 레지스트리는 태그 목록과 노드의 pull 이벤트, 로그는 Loki에 저장된 줄, 메트릭은 Prometheus 시계열로 본다.
- 목(mock)은 없다. Slack이나 AI 자동화로 실제 알림을 보내지 않는 대신, `alerts`는 라우팅 설정만 읽는다. 실제 전달까지 확인하려면 AI_auto_pipeline 쪽 검증(`verify-aiops`)과 운영자 허락이 필요하다.

## Cleanup

```bash
RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/cleanup.sh
```

이 실행의 `verify-k3s-<RUN_ID>` namespace(소유 라벨이 맞을 때만)와 레지스트리의 `verify-k3s/busybox:<RUN_ID>` 매니페스트, 맥 Docker의 같은 태그만 지운다. VM과 클러스터, 다른 namespace, 증거는 남긴다. 프로세스 이름으로 죽이지 않는다. 클러스터를 끄는 것(`vagrant halt`)은 운영자가 정한다.

## Helpers

`bin/` 아래 다섯 개가 전부다. 모두 실행 권한이 있다.

- `_env.sh`는 공통 값이다. 경로, `KUBECONFIG`, 인벤토리와 `all.yml`에서 읽은 주소와 포트, `RUN_ID`에서 만드는 `NS`와 `EVIDENCE`가 들어 있다.
- `launch.sh`, `doctor.sh`, `drive.sh`, `cleanup.sh`는 위 절에 나온 대로 부른다.

새 기능을 검증하려면 `drive.sh`에 `drive_<이름>` 함수를 추가하고 `features/`에 같은 이름의 파일을 만든다.
