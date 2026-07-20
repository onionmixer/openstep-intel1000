#!/bin/bash
# nxrun.sh - OPENSTEP에 telnet으로 자동 로그인해 csh 명령 한 줄을 실행.
# 원격 명령의 exit status를 그대로 반환한다.
#
#   ./tools/nxrun.sh 'ls /ndrv'
#   NXRUN_TIMEOUT=600 ./tools/nxrun.sh 'cd /ndrv/foo && make'
#
# 주의: 원격 셸은 csh다 — 리다이렉트는 >& , mkdir -p 없음.
set -u
. "$(dirname "$0")/site.sh"
HOST="$NEXT_HOST"
TMO="${NXRUN_TIMEOUT:-180}"
[ $# -ge 1 ] || { echo "usage: $0 '<csh command>'" >&2; exit 2; }
command -v expect >/dev/null 2>&1 || { echo "nxrun: expect not installed" >&2; exit 2; }

exec expect -f - "$HOST" "$TMO" "$*" <<'EOS'
set host    [lindex $argv 0]
set timeout [lindex $argv 1]
set cmd     [lindex $argv 2]
log_user 0
set env(TERM) vt100
spawn telnet $host
expect {
    -re {login: ?$}  { send "root\r" }
    timeout          { puts stderr "nxrun: no login prompt"; exit 2 }
    eof              { puts stderr "nxrun: connect failed (booted into Haiku? machine off?)"; exit 2 }
}
expect {
    -re {Password: ?}         { send "\r"; exp_continue }
    -re {TERM = \(unknown\)}  { send "vt100\r"; exp_continue }
    -re {nextonion:[0-9]+#} {}
    timeout           { puts stderr "nxrun: no shell prompt"; exit 2 }
}
log_user 1
send -- "$cmd\r"
expect {
    -re {nextonion:[0-9]+#} {}
    timeout { puts stderr "\nnxrun: command timeout (${timeout}s)"; exit 3 }
}
log_user 0
send -- {echo NXRUN_STATUS=$status}
send "\r"
set rc 3
expect {
    -re {NXRUN_STATUS=([0-9]+)} { set rc $expect_out(1,string) }
    timeout {}
}
send "logout\r"
expect eof
exit $rc
EOS
