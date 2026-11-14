# Headlamp 웹 UI

`http://192.168.56.10:30003`에서 Headlamp가 뜨고, 프로젝트 폴더의 `headlamp-token.txt` 토큰으로 로그인한다. 토큰은 `headlamp` namespace의 `headlamp-admin` 서비스 계정(cluster-admin)이다.

## Sub-features

- `headlamp-page`: 웹 UI가 200과 Headlamp 페이지를 돌려준다.
- `headlamp-token`: 토큰이 API 서버에서 headlamp-admin으로 인증된다.
- `headlamp-rbac`: 그 토큰으로 전체 namespace의 Pod를 볼 수 있다.

## How to get to it (user POV)

- 브라우저로 `http://192.168.56.10:30003`을 열고 토큰을 붙여 넣는다.

## Driving it with verify-k3s-lab

Preconditions:

- doctor의 Headlamp와 인증 파일 항목이 OK.

- **웹 UI와 토큰.** `RUN_ID=$RUN_ID .claude/skills/verify-k3s-lab/bin/drive.sh headlamp`. `drive.log`에 `[headlamp] PASS` 두 줄.
- **증명.** `headlamp.index.html`, `headlamp.whoami.json`(username `system:serviceaccount:headlamp:headlamp-admin`), `headlamp.can-i.json`(`allowed: true`).

## Gotchas

- 이 drive는 Headlamp가 로그인 때 하는 일(토큰으로 API 서버 호출)을 맥에서 같은 토큰으로 재현한다. 브라우저 화면의 로그인 흐름 자체는 보지 않는다. 화면까지 증명해야 하면 브라우저 도구로 토큰을 넣고 Pod 목록 화면을 캡처한다.
- 토큰 인증은 kubeconfig의 클라이언트 인증서가 섞이지 않도록 `kubectl --token`이 아니라 curl과 kubeconfig의 CA로 한다.
