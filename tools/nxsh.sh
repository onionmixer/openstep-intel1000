#!/bin/bash
# nxsh.sh - OPENSTEP 대화형 telnet 세션 (root 자동 로그인).
# 종료는 원격에서 logout 또는 Ctrl-] 후 quit.
set -u
. "$(dirname "$0")/site.sh"
HOST="$NEXT_HOST"
command -v expect >/dev/null 2>&1 || { echo "nxsh: expect not installed" >&2; exit 2; }

exec expect -f - "$HOST" <<'EOS'
set host [lindex $argv 0]
set timeout 30
set env(TERM) vt100
spawn telnet $host
expect {
    -re {login: ?$}  { send "root\r" }
    timeout          { puts stderr "nxsh: no login prompt"; exit 2 }
    eof              { puts stderr "nxsh: connect failed (booted into Haiku? machine off?)"; exit 2 }
}
expect {
    -re {Password: ?}         { send "\r"; exp_continue }
    -re {TERM = \(unknown\)}  { send "vt100\r"; exp_continue }
    -re "$env(NEXT_PROMPT)" {}
    timeout           { puts stderr "nxsh: no shell prompt"; exit 2 }
}
interact
EOS
