#!/bin/bash
# nx-daemon.sh - OPENSTEP의 gcdsd 데몬을 배포/기동/확인한다.
#
#   ./tools/nx-daemon.sh status     # 포트 응답 확인
#   ./tools/nx-daemon.sh start      # /me/gcdsd 기동
#   ./tools/nx-daemon.sh deploy     # 바이너리+설정 배포 후 기동
#
# 데몬은 부팅 시 자동으로 뜨지 않는다. 머신을 재부팅했으면 start.
# deploy는 NFS 마운트가 되어 있어야 한다(remote/ 를 원격에서 읽는다).
set -u
. "$(dirname "$0")/site.sh"

NXRUN="$ROOT/tools/nxrun.sh"
GCDS_ROOT="${GCDS_ROOT:-$(cd "$ROOT/../GrandCrossDevServer" 2>/dev/null && pwd)}"

status() {
    if nc -z -w3 "$NEXT_HOST" "$GCDS_PORT" 2>/dev/null; then
        echo "gcdsd: ${NEXT_HOST}:${GCDS_PORT} 응답함"
        return 0
    fi
    echo "gcdsd: ${NEXT_HOST}:${GCDS_PORT} 무응답"
    return 1
}

case "${1:-status}" in
    status)
        status ;;

    start)
        "$NXRUN" "cd /me ; nohup ./gcdsd & ; sleep 1 ; ps aux | grep gcdsd | grep -v grep"
        sleep 1
        status ;;

    deploy)
        if [ ! -f "$ROOT/remote/gcdsd" ]; then
            if [ -f "$GCDS_ROOT/dist/next/gcdsd" ]; then
                mkdir -p "$ROOT/remote"
                cp "$GCDS_ROOT/dist/next/gcdsd" "$ROOT/remote/gcdsd"
            else
                echo "nx-daemon: remote/gcdsd 가 없습니다." >&2
                echo "           GCDS의 dist/next/gcdsd 를 복사해 두세요." >&2
                exit 2
            fi
        fi
        [ -f "$ROOT/remote/gcdsd.cnf" ] || "$ROOT/tools/gen-conf.sh"

        "$NXRUN" "cp ${MOUNTPT}/remote/gcdsd /me/gcdsd ; \
cp ${MOUNTPT}/remote/gcdsd.cnf /me/gcdsd.cnf ; chmod 755 /me/gcdsd ; ls -l /me/gcdsd"
        "$0" start ;;

    *)
        echo "usage: $0 {status|start|deploy}" >&2
        exit 2 ;;
esac
