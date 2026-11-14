# Pod 로그 수집

Pod가 stdout에 찍은 줄은 k3s-w2의 Alloy가 모아 Loki에 보내고, Grafana의 Loki 데이터소스(uid `loki`)에서 `namespace`, `pod`, `container`, `service`, `node` 라벨로 조회된다.

## Sub-features

- `logs-collect`: 새 Pod의 stdout이 Loki에 들어간다.
- `logs-labels`: `namespace` 라벨로 걸러진다.
- `logs-grafana`: Grafana 데이터소스 프록시를 거쳐 조회된다(Explore 화면이 부르는 경로).

## How to get to it (user POV)

- Grafana(`http://192.168.56.10:30030`, admin / `grafana-admin-password.txt`) → Explore → Loki → `{namespace="<ns>"}`

## Driving it with verify-k3s-lab

Preconditions:

- doctor의 Grafana 항목이 OK. `monitoring` namespace에서 `alloy`와 `loki-0`이 Running.

- **수집.** `RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh logs`. `logs-probe` Pod가 `verify-k3s-<RUN_ID>-logs`를 찍고, 2분 동안 `{namespace="verify-k3s-<RUN_ID>"} |= "<표지>"`를 조회한다. `drive.log`에 `[logs] PASS`가 있다.
- **증명.** `logs.loki.json`의 `data.result[0].values`에 표지 문자열이 있다.

## Gotchas

- 수집까지 수 초에서 수십 초 걸린다. 고정 sleep 대신 drive.sh처럼 조회를 반복한다.
- Loki에 직접 push하면 Alloy 경로를 건너뛰므로 증명이 아니다.
- 표지는 RUN_ID마다 하나라, 같은 RUN_ID로 다시 돌리면 처음 찍힌 줄을 다시 찾는다. 조회 범위가 최근 15분이므로 그보다 늦게 다시 돌리면 새 RUN_ID로 launch한다.
