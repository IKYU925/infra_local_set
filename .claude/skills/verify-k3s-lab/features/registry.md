# 로컬 이미지 레지스트리

맥에서 빌드한 이미지를 `192.168.56.10:30500/<이름>:<태그>`로 push하면, 모든 노드의 containerd가 같은 주소에서 TLS 없이 pull한다. 레지스트리는 registry 역할이 k3s-cp에 띄우고, 미러 설정은 각 노드의 `/etc/rancher/k3s/registries.yaml`이다.

## Sub-features

- `registry-push`: 맥 `docker push`가 성공하고 태그 목록(`/v2/<이름>/tags/list`)에 나온다.
- `registry-pull`: 노드가 그 이미지로 Pod를 띄운다(이벤트 `Successfully pulled image`).
- `registry-catalog`: `/v2/_catalog`로 저장소 목록을 본다.

## How to get to it (user POV)

- `docker build -t 192.168.56.10:30500/<이름>:<태그> . && docker push ...` (README 레지스트리 절)
- 매니페스트의 `image: 192.168.56.10:30500/<이름>:<태그>`

## Driving it with verify-k3s-lab

Preconditions:

- Docker Desktop이 켜져 있고 `docker info`의 insecure-registries에 `192.168.56.10:30500`이 있다.
- doctor의 `레지스트리 응답` 항목이 OK.

- **push와 pull.** `RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh registry`. busybox:1.36을 `verify-k3s/busybox:<RUN_ID>`로 push하고, 그 이미지로 k3s-w1에 Pod를 띄운다. `drive.log`에 PASS 두 줄(태그 목록, pull 이벤트)이 있다.
- **증명.** `registry.push.log`, `registry.tags.json`, `registry.events.txt`.
- **정리.** cleanup이 `registry.env`의 digest로 매니페스트를 지운다.

## Gotchas

- Docker가 꺼져 있으면 `Docker 데몬이 꺼져 있다`로 FAIL이다. `/v2/` 응답만 보고 PASS로 바꾸지 않는다.
- 매니페스트를 지워도 blob은 레지스트리 가비지 컬렉션 전까지 PVC에 남는다. busybox라 수 MB다.
- 다른 세션의 `aiops/*` 저장소는 건드리지 않는다. 검증은 `verify-k3s/*`만 쓴다.
- 맥 Docker가 arm64 이미지를 받으므로 VM(arm64)과 맞다. 다른 아키텍처 태그를 push하면 Pod가 `exec format error`로 죽는다.
