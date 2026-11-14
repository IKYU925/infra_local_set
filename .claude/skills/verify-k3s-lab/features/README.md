# K3s 실습 클러스터 검증 지도

검증할 때 먼저 이 색인을 읽고, 맞는 기능 파일을 절차로 쓴다. 이 지도가 검증의 기준이다. 편한 진입점 하나만 확인한 증명은, 지도에 다른 진입점이 있으면 완료가 아니다.

## 기본 전제

- `launch.sh`가 `ready`와 `RUN_ID`를 출력했고 `RUN_ID=$RUN_ID doctor.sh`가 모두 OK다.
- 클러스터는 다른 세션과 공유한다. 검증 namespace(`verify-k3s-<RUN_ID>`) 밖에는 쓰지 않는다(SKILL.md 격리 규칙).

## 실행 규칙

- 모든 명령은 저장소 루트에서 그대로 실행한다.
- 기능 단위 실행은 `RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh <기능>`이다. 기능끼리 순서와 무관하다.
- 같은 RUN_ID로 같은 기능을 다시 돌려도 된다. Pod는 `kubectl apply`로 같은 이름을 쓰고, 이미 있으면 그대로 둔다.

## 증명과 건너뜀 보고

- 증거는 `verify-results/<RUN_ID>/`의 `drive.log` PASS 줄과 기능별 응답 파일이다.
- 실행하지 못한 진입점은 시도한 명령과 충족되지 않은 전제를 적는다. 다른 경로로 확인했다고 보고하지 않는다. 예를 들어 Docker가 꺼져 `registry`가 FAIL이면, 레지스트리 `/v2/` 응답만으로 push/pull을 확인했다고 하지 않는다.

## 기능 항목 형식

각 파일은 H1 제목과 사용자에게 보이는 동작 한 단락, 그리고 `Sub-features`, `How to get to it (user POV)`, `Driving it with verify-k3s-lab`, `Gotchas` 네 개의 H2로 이뤄진다.

## 기능

- [노드 배치 라벨](placement.md)은 `workload=app`과 `workload=monitoring` nodeSelector가 정해진 워커로 가는지 다룬다.
- [로컬 이미지 레지스트리](registry.md)는 맥에서 push한 이미지를 노드가 받아 Pod를 띄우는지 다룬다(Docker 필요).
- [Pod 로그 수집](logs.md)은 Pod stdout이 Alloy와 Loki를 거쳐 Grafana에서 조회되는지 다룬다.
- [메트릭 수집](metrics.md)은 Prometheus가 새 Pod와 수집 대상을 보는지 다룬다.
- [알림 라우팅](alerts.md)은 Alertmanager가 앱 namespace와 노드 장애 알림을 AI 자동화 웹훅으로 보내도록 설정됐는지 다룬다.
- [Headlamp 웹 UI](headlamp.md)는 웹 UI 응답과 로그인 토큰의 인증, 권한을 다룬다.
