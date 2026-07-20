#!/bin/bash
# nx-install-driver.sh - 드라이버 번들을 실기에 빌드·설치하고 검증한다.
#
#   ./tools/nx-install-driver.sh openstep-intel1000/Pro1000       # 빌드+설치+검증
#   ./tools/nx-install-driver.sh openstep-intel1000/Pro1000 -n    # 빌드만
#
# 경로는 워크스페이스 루트 기준이며, 실기에서는 $MOUNTPT 아래로 읽는다.
#
# **설치 후 파일 크기를 반드시 확인한다.** 0바이트 번들을 남기면
# 부팅 시 driverLoader가 그것을 읽으려다 kern_loader가 무한 루프에
# 빠진다(2026-07-20에 실제로 겪었다 — 크래시 중 복사가 끊겨 디렉터리
# 항목만 남고 내용이 유실됐고, 이후 부팅마다 kern_loader가 CPU를
# 태웠다). 크기 검증에 실패하면 설치본을 지우고 실패로 끝낸다.
set -u
. "$(dirname "$0")/site.sh"

NX="$ROOT/tools/nx.sh"
SRC="${1:?usage: $0 <bundle-dir-relative-to-workspace> [-n]}"
BUILD_ONLY="${2:-}"

NAME="$(basename "$SRC")"
TMP="/tmp/$NAME"
DEST="/private/Devices/$NAME.config"

echo "== 빌드: $SRC -> $TMP"
"$NX" "rm -rf $TMP && cp -r $MOUNTPT/$SRC $TMP && cd $TMP && make 2>&1 | tail -3" \
    || { echo "빌드 실패" >&2; exit 1; }

RELOC="$TMP/$NAME.config/${NAME}_reloc"
SIZE=$("$NX" "wc -c < $RELOC" 2>/dev/null | tr -d ' \r')
if [ -z "$SIZE" ] || [ "$SIZE" -lt 1000 ]; then
    echo "빌드 산출물이 비었거나 너무 작다 (${SIZE:-0} bytes): $RELOC" >&2
    exit 1
fi
echo "== 빌드 OK: ${NAME}_reloc = $SIZE bytes"

[ "$BUILD_ONLY" = "-n" ] && exit 0

# 이미 로드된 드라이버를 언로드하지 않는다.
#
# 네트워크 스택에 붙은(attachToNetworkWithAddress:) 드라이버를
# 언로드하면 커널이 사라진 모듈을 가리켜 **패닉**한다 — NextDev 문서가
# 명시한 동작이고 2026-07-20에 실제로 그렇게 죽였다. 로드돼 있으면
# 설치만 하고, 반영은 재부팅 후에 한다.
LOADED=$("$NX" "/usr/etc/kl_util -s $NAME 2>&1 | grep STATUS" 2>/dev/null)
case "$LOADED" in
    *Loaded*)
        echo "!! $NAME 이 이미 로드돼 있다: $LOADED" >&2
        echo "!! 언로드하지 않는다 — 네트워크 스택에 붙은 드라이버를" >&2
        echo "!! 언로드하면 커널이 패닉한다. 새 번들은 설치하되," >&2
        echo "!! **반영하려면 재부팅**해야 한다." >&2
        NEED_REBOOT=1 ;;
    *)
        NEED_REBOOT=0
        "$NX" "/usr/etc/kl_util -d $NAME" >/dev/null 2>&1 ;;
esac

echo "== 설치: $DEST"
"$NX" "rm -rf $DEST && cp -r $TMP/$NAME.config /private/Devices/ && sync"

# 검증: 설치본의 relocatable 크기가 빌드본과 같아야 한다.
INSTALLED=$("$NX" "wc -c < $DEST/${NAME}_reloc" 2>/dev/null | tr -d ' \r')
if [ "${INSTALLED:-0}" != "$SIZE" ]; then
    echo "설치 검증 실패: $DEST/${NAME}_reloc = ${INSTALLED:-0} bytes" \
         "(빌드본 $SIZE)" >&2
    echo "0바이트 번들은 부팅 시 kern_loader를 멈춘다 - 설치본을 지운다." >&2
    "$NX" "rm -rf $DEST"
    exit 1
fi

echo "== 설치 검증 OK: ${NAME}_reloc = $INSTALLED bytes"
"$NX" "ls -l $DEST"

if [ "${NEED_REBOOT:-0}" = 1 ]; then
    echo
    echo "*** 새 번들은 설치됐지만 아직 커널에 반영되지 않았다."
    echo "*** 이전 버전이 로드된 상태이므로 재부팅이 필요하다."
fi
