#!/bin/bash
# nx.sh - OPENSTEP 원격 실행 단축 래퍼 (gcds 경유).
#
#   ./tools/nx.sh 'cd /ndrv/pcils && make'
#   ./tools/nx.sh --get /tmp/out.txt local.txt
#   ./tools/nx.sh --put local.txt /tmp/in.txt
#
# gcds 바이너리는 이 워크스페이스의 bin/gcds 를 쓴다 (GrandCrossDevServer
# 쪽 빌드 산출물이 정리돼 사라지는 일이 있어 사본을 둔다).
# 없으면 GCDS 소스에서 자동 재빌드한다.
set -u
. "$(dirname "$0")/site.sh"
GCDS="$ROOT/bin/gcds"
GCDS_ROOT="${GCDS_ROOT:-$(cd "$ROOT/../GrandCrossDevServer" 2>/dev/null && pwd)}"

if [ ! -x "$GCDS" ]; then
    echo "nx: bin/gcds missing - rebuilding from $GCDS_ROOT" >&2
    ( cd "$GCDS_ROOT" && make -f make/Makefile.posix ) >/dev/null 2>&1
    if [ ! -x "$GCDS_ROOT/gcds" ]; then
        echo "nx: rebuild failed" >&2; exit 2
    fi
    mkdir -p "$ROOT/bin" && cp "$GCDS_ROOT/gcds" "$GCDS"
fi

if [ ! -f "$ROOT/etc/gcds.cnf" ]; then
    "$ROOT/tools/gen-conf.sh" >&2
fi
export GCDS_CONF="$ROOT/etc/gcds.cnf"
case "${1:-}" in
    --get|--put|--ping|--stat)
        op="$1"; shift; exec "$GCDS" "$op" next "$@" ;;
esac
exec "$GCDS" next "$@"
