#!/bin/bash
# site.sh - etc/site.conf 를 읽어 사이트 값을 환경에 올린다.
# 다른 tools/*.sh 가 `. "$(dirname "$0")/site.sh"` 로 가져다 쓴다.
# 단독 실행하면 현재 설정을 보여준다.

_site_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_site_conf="$_site_root/etc/site.conf"

if [ ! -f "$_site_conf" ]; then
    echo "site: $_site_conf 가 없습니다." >&2
    echo "      cp etc/site.conf.sample etc/site.conf 후 값을 채우세요." >&2
    exit 2
fi

# 환경에서 미리 준 값이 site.conf보다 우선한다. 예를 들어 /ndrv 가
# 실패한 soft mount 때문에 "Device busy" 로 잠겨 있을 때
# `MOUNTPT=/ndrv2 ./tools/nx-install-driver.sh ...` 로 우회할 수 있다.
_site_env_mountpt="${MOUNTPT:-}"

. "$_site_conf"

[ -n "$_site_env_mountpt" ] && MOUNTPT="$_site_env_mountpt"

# 파생 값: NFS export 경로는 항상 이 워크스페이스 루트다.
NFS_EXPORT="$_site_root"
ROOT="$_site_root"

: "${NEXT_HOST:?site.conf에 NEXT_HOST가 없습니다}"
: "${NFS_SERVER:?site.conf에 NFS_SERVER가 없습니다}"
: "${MOUNTPT:=/ndrv}"
: "${GCDS_TOKEN:=changeme}"
: "${GCDS_PORT:=9910}"
: "${NEXT_PROMPT:=[a-zA-Z0-9_-]+:[0-9]+#}"

export NEXT_HOST NFS_SERVER NFS_EXPORT MOUNTPT GCDS_TOKEN GCDS_PORT ROOT
export NEXT_PROMPT

if [ "$(basename "${0:-}")" = "site.sh" ]; then
    echo "NEXT_HOST  = $NEXT_HOST"
    echo "NFS_SERVER = $NFS_SERVER"
    echo "NFS_EXPORT = $NFS_EXPORT"
    echo "MOUNTPT    = $MOUNTPT"
    echo "GCDS_PORT  = $GCDS_PORT"
    echo "GCDS_TOKEN = (설정됨)"
fi
