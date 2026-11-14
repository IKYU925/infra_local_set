# 노드 배치 라벨

앱 매니페스트가 `nodeSelector: {workload: app}`을 쓰면 k3s-w1에, 관측 도구가 `{workload: monitoring}`을 쓰면 k3s-w2에 뜬다. 라벨은 `ansible/host_vars/`에서 k3s_agent 역할이 붙인다.

## Sub-features

- `placement-app`: `workload=app` Pod가 k3s-w1에 뜬다.
- `placement-monitoring`: `workload=monitoring` Pod가 k3s-w2에 뜬다.
- `placement-labels`: 노드 라벨 자체가 붙어 있다(doctor가 확인).

## How to get to it (user POV)

- 매니페스트에 `nodeSelector`를 넣고 `kubectl apply`한다.
- `kubectl get nodes -L workload`로 라벨을 본다.

## Driving it with verify-k3s-lab

Preconditions:

- doctor의 `배치 라벨` 항목이 OK.

- **배치.** `RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh placement`. `drive.log`에 `[placement] PASS workload=app Pod가 k3s-w1 에 배치`와 `workload=monitoring ... k3s-w2` 두 줄이 있다.
- **증명.** `placement-app.txt`, `placement-monitoring.txt`의 NODE 열.

## Gotchas

- busybox 이미지는 Docker Hub에서 받는다. VM이 인터넷에 닿지 않으면 Ready가 되지 않고 `*.describe.txt`에 ImagePullBackOff가 남는다.
- 라벨이 없으면 Pod는 Pending으로 남고 3분 뒤 FAIL이다. 라벨을 고치려고 `kubectl label node`를 직접 하지 않는다. 원인은 `host_vars`나 k3s_agent 역할에 있다.
