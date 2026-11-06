#!/usr/bin/env bash
# =============================================================================
# common.sh — 모든 노드 공통 설정 (프로비저닝 1단계)
#
# 목적: K3s 설치 전에 모든 VM이 같은 기본 환경을 갖추도록 한다.
# 역할:
#   - 타임존을 Asia/Seoul 로 맞춘다 (로그 시간 일관성)
#   - 모든 노드를 /etc/hosts 에 등록해 호스트명으로 서로 통신하게 한다
# 실행 위치: controlplane + 모든 worker (master.sh / worker.sh 보다 먼저)
# 인자: "IP 호스트명" 형태의 문자열 목록 (Vagrantfile의 HOSTS)
# 재실행: 안전 (같은 호스트명 줄을 지우고 다시 쓴다)
# =============================================================================
set -euo pipefail

echo "[common] $(hostname) 공통 설정 시작"

timedatectl set-timezone Asia/Seoul || true

# 노드끼리 호스트명으로 통신할 수 있도록 /etc/hosts 등록
# Vagrant가 넣는 "127.0.x.1 <hostname>" 줄은 지워서 호스트명이 private IP로 풀리게 한다
for entry in "$@"; do
  name="${entry##* }"
  sed -i "/[[:space:]]${name}\$/d" /etc/hosts
  echo "$entry" >> /etc/hosts
done

echo "[common] /etc/hosts 등록 완료"
tail -n "$#" /etc/hosts
