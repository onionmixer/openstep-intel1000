#!/bin/bash
# nx-fixroute.sh - 부팅 시 생기는 엉터리 기본 경로를 정리한다.
#
#   ./tools/nx-fixroute.sh          # 확인 후 있으면 삭제
#   ./tools/nx-fixroute.sh -n       # 확인만
#
# OPENSTEP의 부팅 네트워크 설정은 en0만 알고 en1은 모른다(NetInfo에
# 항목이 없다). 그래서 Pro1000이 부팅 시 자동 로드되면 en1이 주소
# 없이(0.0.0.0) 올라오고, 기본 경로가 둘이 된다:
#
#   default   192.0.2.1   UG   en0    ← 정상
#   default   0.0.0.0       U    en1    ← 이것
#
# 지금은 en0 쪽이 쓰이지만 보장된 동작이 아니다. off-subnet 트래픽이
# en1로 새면 진단하기 까다로운 고장이 된다.
#
# `ifconfig en1 down` 으로는 지워지지 않는다 - 경로를 명시적으로
# 삭제해야 한다.
#
# **NIC가 둘인 동안만의 문제다.** 82547EI가 온보드이므로 드라이버가
# 완성되면 tulip을 제거할 계획이고, 그러면 NetInfo가 en1을 정상
# 설정하게 되어 이 스크립트가 필요 없어진다.
#
# telnet 경로를 쓴다 - gcdsd가 죽어 있어도 동작해야 하기 때문.
set -u
. "$(dirname "$0")/site.sh"

NXRUN="$ROOT/tools/nxrun.sh"
CHECK_ONLY="${1:-}"

routes=$("$NXRUN" 'netstat -rn' 2>/dev/null)

if ! echo "$routes" | grep -q "^default *0\.0\.0\.0"; then
    echo "fixroute: 엉터리 기본 경로 없음 (정상)"
    echo "$routes" | grep -E "^default" | sed 's/^/  /'
    exit 0
fi

echo "fixroute: 엉터리 기본 경로 발견"
echo "$routes" | grep -E "^default" | sed 's/^/  /'

if [ "$CHECK_ONLY" = "-n" ]; then
    echo "fixroute: -n 지정됨, 삭제하지 않음"
    exit 0
fi

"$NXRUN" '/usr/etc/route delete default 0.0.0.0' >/dev/null 2>&1

after=$("$NXRUN" 'netstat -rn' 2>/dev/null)
if echo "$after" | grep -q "^default *0\.0\.0\.0"; then
    echo "fixroute: 삭제 실패 - 남아 있음" >&2
    exit 1
fi

echo "fixroute: 삭제 완료. 남은 기본 경로:"
echo "$after" | grep -E "^default" | sed 's/^/  /'
