# S17 실험용 볼륨

k3s-w1에는 S17(승인 후 조치) 실험이 채우는 전용 볼륨이 `/srv/appdata`에 루프 마운트돼 있다. 실험은 루트 디스크 대신 이 볼륨만 채우고, 사용률이 90%를 넘으면 `AppdataDiskFull`이 AI 자동화로 간다. 볼륨은 `host_vars/k3s-w1.yml`의 `appdata_volume_size`가 있을 때 common 역할이 만든다(`/var/lib/appdata.img`, ext4, fstab `loop,nofail`).

## Sub-features

- `appdata-mount`: k3s-w1의 Pod가 hostPath로 본 `/srv/appdata`가 루트와 다른 파일시스템이고 크기가 `appdata_volume_size`에 맞다.
- `appdata-tmp`: `/srv/appdata/tmp` 폴더가 있다.
- `appdata-metrics`: Prometheus의 `node_filesystem_size_bytes{mountpoint="/srv/appdata"}`가 nodename=k3s-w1로 Pod와 같은 크기를 본다.
- `appdata-rule`: `AppdataDiskFull` 규칙이 정확히 1개 로드돼 health ok다.
- `appdata-reboot`: 재부팅 뒤 fstab으로 다시 마운트된다(이 스킬에서는 drive하지 않음).

## How to get to it (user POV)

- 앱 매니페스트에서 `nodeSelector: {workload: app}`과 hostPath `/srv/appdata/tmp`를 쓴다.
- Prometheus UI `http://192.168.56.10:30090`에서 `node_filesystem_avail_bytes{mountpoint="/srv/appdata"}`를 조회한다.
- Prometheus → Alerts에서 `AppdataDiskFull`을 본다.

## Driving it with verify-k3s-lab

Preconditions:

- doctor의 Prometheus 항목이 OK.
- `host_vars/k3s-w1.yml`에 `appdata_volume_size`가 있다(없으면 FAIL).

- **볼륨과 메트릭.** `RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh appdata`. `drive.log`에 `[appdata] PASS` 네 줄(파일시스템 크기, tmp 폴더, Prometheus 같은 크기, 규칙 1개).
- **증명.** `appdata.df.txt`(Pod 안 `df -P`와 `tmp-dir-ok`), `appdata.size.json`, `appdata.rules.json`.

## Gotchas

- 검증 Pod는 볼륨을 읽기 전용으로 마운트한다. 볼륨을 채워서 알림을 확인하지 않는다. 그러면 AI 자동화 파이프라인에 실제 장애가 접수된다. 알림 전달은 AI_auto_pipeline 쪽에서 운영자가 허락할 때 한다.
- 크기 기준은 `appdata_volume_size`의 85~100%다. ext4 메타데이터 때문에 1G 볼륨은 약 973MiB로 보인다.
- `AppdataDiskFull` 규칙이 0개면 AI_auto_pipeline의 `shopapi-alerts`가 배포되지 않은 것이고, 2개 이상이면 누군가 규칙을 중복으로 넣은 것이다. 둘 다 이 레포의 문제가 아니다. 규칙을 이 레포에 추가해서 고치지 않는다.
- `appdata-reboot`는 VM 재부팅이 필요해 공유 클러스터에서 drive하지 않는다. fstab 줄만 있고 실제 재부팅 마운트는 확인되지 않았다.
