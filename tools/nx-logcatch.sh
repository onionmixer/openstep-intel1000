#!/bin/bash
# nx-logcatch.sh - OPENSTEP의 시스템 로그를 NFS 공유로 계속 밀어낸다.
#
#   ./tools/nx-logcatch.sh start   # 수집 시작 (위험한 테스트 전에 실행)
#   ./tools/nx-logcatch.sh stop
#   ./tools/nx-logcatch.sh status
#   ./tools/nx-logcatch.sh show    # 호스트에 쌓인 로그 보기
#
# 커널이 행되면 /usr/adm/messages는 버퍼에 갇힌 채 사라진다. nxlogd가
# 한 줄씩 NFS로 fsync하며 밀어내므로, 행 직전까지의 로그가 호스트
# 디스크(logs/kernel.log)에 남는다.
#
# telnet 경로(nxrun)를 쓴다 — gcdsd가 죽어 있어도 동작해야 하기 때문.
set -u
. "$(dirname "$0")/site.sh"

NXRUN="$ROOT/tools/nxrun.sh"
LOGDIR="$ROOT/logs"
mkdir -p "$LOGDIR"

# 세션마다 새 파일에 남긴다. 한 파일에 계속 붙이면 어떤 사고로 그
# 파일을 잃었을 때 지난 증거까지 함께 사라진다 (실제로 한 번 겪었다).
# latest 심볼릭 링크가 항상 최신을 가리킨다.
STAMP="$(date +%Y%m%d-%H%M%S)"
LOGFILE="$LOGDIR/kernel-$STAMP.log"
REMOTE_LOG="$MOUNTPT/logs/kernel-$STAMP.log"
LATEST="$LOGDIR/latest.log"

case "${1:-status}" in
    start)
        # 실기에 빌드본이 없으면 만든다 (NFS 공유의 소스를 그대로 쓴다)
        "$NXRUN" "if (! -e /tmp/nxlogd) cc -O -o /tmp/nxlogd ${MOUNTPT}/tools/nxlogd.c" \
            >/dev/null 2>&1
        "$NXRUN" "nohup /tmp/nxlogd /usr/adm/messages ${REMOTE_LOG} >& /dev/null &" \
            >/dev/null 2>&1
        sleep 2
        ln -sf "$(basename "$LOGFILE")" "$LATEST"
        if [ -s "$LOGFILE" ]; then
            echo "logcatch: 수집 중 -> $LOGFILE  (logs/latest.log)"
            tail -1 "$LOGFILE"
        else
            echo "logcatch: 시작했으나 아직 기록 없음 ($LOGFILE)" >&2
        fi ;;

    stop)
        # NeXT의 csh/ps 조합에서 파이프라인 인용이 까다로워, pid를 먼저
        # 받아 호스트에서 조립한다.
        pids=$("$NXRUN" 'ps ax | grep nxlogd' 2>/dev/null \
               | grep -v grep | grep nxlogd | awk '{print $1}' | tr '\n' ' ')
        if [ -n "${pids// /}" ]; then
            "$NXRUN" "kill $pids" >/dev/null 2>&1
            echo "logcatch: 중지함 (pid $pids)"
        else
            echo "logcatch: 실행 중인 nxlogd 없음"
        fi ;;

    status)
        "$NXRUN" 'ps ax | grep nxlogd | grep -v grep' 2>&1 | tail -3
        if [ -e "$LATEST" ]; then
            echo "최신 로그: $(readlink -f "$LATEST") ($(wc -l < "$LATEST") 줄)"
        fi
        ls -1t "$LOGDIR"/kernel-*.log 2>/dev/null | head -5 ;;

    show)
        shift
        tail "${@:--40}" "$LATEST" ;;

    *)
        echo "usage: $0 {start|stop|status|show}" >&2
        exit 2 ;;
esac
