# 메트릭 수집

kube-prometheus-stack의 Prometheus(k3s-w2)가 kube-state-metrics, node-exporter, ServiceMonitor 대상을 수집한다. 새 Pod는 `kube_pod_info`에 node 라벨과 함께 나타난다.

## Sub-features

- `metrics-pod`: 새 Pod가 `kube_pod_info`에 잡힌다.
- `metrics-targets`: 수집 대상의 health(down인 job 목록)를 본다.
- `metrics-servicemonitor`: 앱의 ServiceMonitor가 대상에 들어온다(`serviceMonitorSelectorNilUsesHelmValues: false`라 namespace와 라벨에 상관없이 잡힌다).

## How to get to it (user POV)

- Prometheus UI `http://192.168.56.10:30090` → Query, Status → Targets
- Grafana → Explore → Prometheus

## Driving it with verify-k3s-lab

Preconditions:

- doctor의 Prometheus 항목이 OK.

- **새 Pod.** `RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh metrics`. 2분 안에 `kube_pod_info{namespace="verify-k3s-<RUN_ID>",pod="metrics-probe"}`가 node=k3s-w1로 나오면 `[metrics] PASS`.
- **수집 대상.** 같은 실행이 `[metrics] INFO down 상태 수집 대상 job: [...]`를 남긴다. 판정이 아닌 정보다. 빈 목록이 정상이다.
- **증명.** `metrics.kube_pod_info.json`, `metrics.targets.json`.

## Gotchas

- `metrics-servicemonitor`는 아직 drive가 없다. 앱 쪽 ServiceMonitor(예 `shop` namespace의 shopapi)는 `metrics.targets.json`에서 job 이름으로 찾을 수 있지만, 검증 Pod는 메트릭 엔드포인트가 없어 직접 증명하지 못한다.
