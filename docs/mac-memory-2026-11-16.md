# 맥 메모리 부족과 k3s-cp 증설 메모 (2026-11-16)

## 상황

- 맥(16GB)에서 "메모리 부족" 팝업이 떴다.
- k3s-cp에서 k3s가 부팅 후 2번 재시작했다(NRestarts=2). 그 여파로 AI_auto_pipeline 측정이 두 번 깨졌다.

## 측정값

맥(`vm_stat`, `sysctl vm.swapusage`, `top -o mem`):

| 항목 | 값 |
|---|---|
| swap 사용 | 10,152~10,292MB / 11,264MB |
| 압축기가 차지한 RAM | 7.4GiB (압축 원본 29.9GiB) |
| `memory_pressure` free | 37% |
| Docker Desktop VM (com.apple.Virtualization) | MEM 8,209M, 메모리 설정 없음(기본값) |
| VBoxHeadless (k3s VM 3대) | 8,149M / 8,143M / 4,053M |

VM 안(`free -m`):

| 노드 | 배정 | used | available |
|---|---|---|---|
| k3s-cp | 2GB | 1,497MB | 330MB |
| k3s-w1 | 4GB | 1,718MB | 2,055MB |
| k3s-w2 | 4GB | 1,830MB | 1,944MB |

k3s-cp 기준값(reload 전): pgmajfault 2,552,932, NRestarts=2.

## 판단

- 원인은 워크로드 크기가 아니라 VM 배분이다. k3s VM 10GB와 Docker Desktop VM 8GB를 합치면 18GB로, 맥 RAM 16GB를 넘는다.
- 클러스터 실제 사용량은 약 5GB다. AWS로 옮길 이유는 아직 없다.
- k3s-cp 2GB는 실제로 작다. 3GB로 올린다.
- 워커 메모리는 줄이지 않는다(w1 requests 2504Mi, w2는 Prometheus와 Loki가 커진다).

## 남은 작업

1. Docker Desktop 메모리를 3~4GB로 내리고, 빌드할 때만 켠다.
2. AI_auto_pipeline S11 측정이 끝나면 `vagrant reload k3s-cp`로 cp 3GB를 적용한다. `vagrant destroy`는 하지 않는다.
3. 노드 3개 Ready 뒤 `count(kube_pod_info)`와 Running Pod 수를 비교한다. 다르면 kube-state-metrics를 재시작한다.
4. cp available(1GB 초과 목표), 부팅 직후와 30분 뒤 pgmajfault, NRestarts, 맥 free 비율과 swap을 기록해 PR #11에 채운다.
5. Docker를 끈 상태에서도 맥 swap이 계속 늘거나 cp available이 1GB 아래면 AWS나 더 큰 머신을 검토한다.

## 그 밖에

- 맥 kubectl 기본 컨텍스트는 `orbstack`이다. 이 클러스터는 `export KUBECONFIG=$PWD/kubeconfig`로 본다.
- 2026-11-16 16:44에 kube-prometheus-stack Helm 리비전 3이 `pending-upgrade`로 멈췄다. 값이 리비전 2와 같아 `helm rollback ... 2`로 풀었다. 멈춘 원인은 확인하지 못했다.
