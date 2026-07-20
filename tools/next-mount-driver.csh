#!/bin/csh -f
#
# next-mount-driver.csh - NeXT_DRIVER 소스 트리를 OPENSTEP에 NFS mount.
# GrandCrossDevServer의 next-mount.csh를 이 프로젝트 기본값으로 고정한
# 사본. OPENSTEP 루트(/)에 복사해 두고 쓴다:
#
#   cp /ndrv/tools/next-mount-driver.csh /next-mount-driver.csh
#
# 사용 (root):
#   /next-mount-driver.csh          # mount (이미 마운트돼 있으면 재mount)
#   /next-mount-driver.csh -u       # unmount만
#
# 호스트에서 소스를 고친 뒤에는 이 스크립트를 다시 실행한다
# (umount→mount로 NeXTSTEP NFS 속성 캐시를 비운다).

set server  = 192.0.2.16
set export  = /path/to/NeXT_DRIVER
set mountpt = /ndrv
set opts = "soft,intr,timeo=30,retrans=5,noac"

set unmount_only = 0
if ("$1" == "-u" || "$1" == "unmount") then
    set unmount_only = 1
else
    if ("$1" != "") set server  = "$1"
    if ("$2" != "") set export  = "$2"
    if ("$3" != "") set mountpt = "$3"
endif

set me = `whoami`
if ("$me" != "root") then
    echo "next-mount-driver: must run as root."
    exit 1
endif

umount $mountpt >& /dev/null

if ($unmount_only) then
    echo "next-mount-driver: $mountpt unmounted."
    exit 0
endif

# NeXTSTEP mkdir has no -p (would create a dir literally named "-p")
if (! -d $mountpt) then
    mkdir $mountpt
    if ($status != 0) then
        echo "next-mount-driver: cannot create $mountpt"
        exit 1
    endif
endif

echo "next-mount-driver: mounting ${server}:${export} on ${mountpt}"
mount -t nfs -o $opts ${server}:${export} $mountpt
if ($status != 0) then
    echo "next-mount-driver: MOUNT FAILED."
    echo "  - is gnfsd running on ${server}?  (sudo tools/serve-src.sh)"
    echo "  - reachable?  try:  ping ${server}"
    exit 1
endif

echo "next-mount-driver: mounted OK.  ${mountpt} contains:"
ls $mountpt
exit 0
