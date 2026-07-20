#!/bin/bash
# nx-mount.sh - OPENSTEP에서 이 워크스페이스를 NFS mount 한다.
#
#   ./tools/nx-mount.sh        # mount (이미 돼 있으면 재mount = 캐시 갱신)
#   ./tools/nx-mount.sh -u     # unmount
#
# 마운트 명령을 telnet으로 직접 보내므로 대상 머신에 스크립트를 미리
# 설치해 둘 필요가 없다 (마운트 전에는 공유 안의 스크립트를 읽을 수
# 없으니 그 편이 순환 의존이 없다).
#
# 호스트에서 소스를 고친 뒤 OPENSTEP이 바뀐 내용을 못 볼 때도 이걸
# 다시 실행하면 된다 - umount→mount가 NeXTSTEP의 NFS 속성 캐시를
# 비운다.
set -u
. "$(dirname "$0")/site.sh"

NXRUN="$ROOT/tools/nxrun.sh"
#
# Mount options. gnfsd is single-threaded (one request at a time), and
# `noac' turns off the client's attribute cache so every lookup reaches
# it - a build walking hundreds of files generates a flood of GETATTRs.
# With the original timeo=10 (1.0 s) and retrans=3, one slow reply was
# enough to fail an operation, and a failed soft mount leaves NeXTSTEP
# holding stale state that makes the next mount report "Device busy".
#
#   soft     fail an operation rather than hang forever if gnfsd dies
#   intr     let Ctrl-C break out of a stuck call
#   timeo=30 3.0 s before the first retry - room for a busy single
#            threaded server to catch up
#   retrans=5 five tries before a soft mount gives up
#   noac     no attribute caching, so host-side edits are seen at once.
#            Kept deliberately: relying on remounts instead would
#            eventually mean building from stale sources.
#
OPTS="soft,intr,timeo=30,retrans=5,noac"

if [ "${1:-}" = "-u" ]; then
    exec "$NXRUN" "umount $MOUNTPT ; echo unmounted $MOUNTPT"
fi

if ! ss -ulnp 2>/dev/null | grep -q ':2049 '; then
    echo "nx-mount: gnfsd가 떠 있지 않습니다." >&2
    echo "          먼저: sudo ./tools/serve-src.sh" >&2
    exit 1
fi

# NeXTSTEP mkdir에는 -p가 없다 - 있으면 "-p"라는 디렉터리가 생긴다.
"$NXRUN" "umount $MOUNTPT ; if (! -d $MOUNTPT) mkdir $MOUNTPT ; \
mount -t nfs -o $OPTS ${NFS_SERVER}:${NFS_EXPORT} $MOUNTPT && ls $MOUNTPT"
