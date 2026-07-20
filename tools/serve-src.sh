#!/bin/bash
# serve-src.sh - 이 워크스페이스(NeXT_DRIVER 루트)를 gnfsd로 export.
# GrandCrossDevServer의 nfsd/serve.sh를 그대로 사용한다.
#
#   sudo ./tools/serve-src.sh          # portmap 111 = root 필요
#   sudo ./tools/serve-src.sh -v -f    # verbose + foreground
#
# OPENSTEP 쪽에서는 /next-mount-driver.csh (tools/next-mount-driver.csh)
# 로 /ndrv에 mount한다.
set -u
GCDS_ROOT="${GCDS_ROOT:-/mnt/USERS/onion/DATA_ORIGN/Workspace/GrandCrossDevServer}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -x "$GCDS_ROOT/nfsd/serve.sh" ]; then
    echo "serve-src: $GCDS_ROOT/nfsd/serve.sh not found (set GCDS_ROOT)" >&2
    exit 2
fi
exec "$GCDS_ROOT/nfsd/serve.sh" "$@" "$ROOT"
