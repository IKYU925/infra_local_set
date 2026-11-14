# 알림 라우팅

Alertmanager는 `shop`, `aiops` namespace에서 정해 둔 알림 다섯 개(`ShopapiException`, `ShopapiHighErrorRate`, `ShopapiSlowPayment`, `PodOOMKilled`, `KubePodCrashLooping`)와 노드 장애 알림(`KubeNodeNotReady`)을 AI 장애 대응 자동화 웹훅(`ai_automation_webhook_url`)으로 Bearer 토큰과 함께 보낸다. `Watchdog`과 `InfoInhibitor`는 버린다. 설정은 monitoring 역할의 `kube-prometheus-stack.values.yaml.j2`다.

## Sub-features

- `alerts-receiver`: ai-automation receiver가 실제 웹훅 URL을 가진다.
- `alerts-namespace-route`: 앱 namespace 매처가 ai-automation으로 간다.
- `alerts-node-route`: 노드 장애 알림이 namespace 없이도 간다.
- `alerts-isolation`: 검증 namespace는 매처에 걸리지 않는다.
- `alerts-delivery`: 실제 알림이 자동화 API에 접수된다(이 스킬에서는 drive하지 않음).

## How to get to it (user POV)

- Alertmanager UI `http://192.168.56.10:30093` → Status
- 앱 namespace에서 PrometheusRule이 발화하면 AI 자동화에 장애가 접수된다.

## Driving it with verify-k3s-lab

Preconditions:

- doctor의 Alertmanager 항목이 OK.

- **설정.** `RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh alerts`. `drive.log`에 `[alerts] PASS` 네 줄(receiver, namespace 매처, 노드 장애, 검증 namespace 비해당).
- **증명.** `alerts.status.json`(실제 적용된 라우트), `alerts.webhook-urls.txt`(설정 Secret의 URL).

## Gotchas

- `/api/v2/status`는 웹훅 URL을 `<secret>`으로 가린다. URL은 `monitoring` namespace의 `alertmanager-kube-prometheus-stack-alertmanager-generated` Secret(gzip)에서 읽는다. 읽기만 한다.
- `alerts-delivery`는 drive하지 않는다. 검증하려면 `shop`이나 `aiops`에서 알림을 일으켜야 하고, 그러면 다른 세션의 자동화 파이프라인이 장애를 접수한다. 운영자가 허락할 때만, AI_auto_pipeline 쪽에서 한다.
- 검증 namespace 이름을 `shop`이나 `aiops`로 시작하게 바꾸지 않는다. 매처가 정규식이라 걸릴 수 있다.
