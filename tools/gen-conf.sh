#!/bin/bash
# gen-conf.sh - etc/site.conf 에서 파생 설정파일을 생성한다.
#
#   etc/gcds.cnf      gcds 클라이언트 설정 (호스트에서 사용)
#   remote/gcdsd.cnf  OPENSTEP에 배포할 데몬 설정
#
# 두 파일 모두 실제 토큰을 담으므로 gitignore된다. site.conf를 고친
# 뒤에는 이 스크립트를 다시 돌리고, gcdsd.cnf는 원격에 재배포한다.
set -eu
. "$(dirname "$0")/site.sh"

mkdir -p "$ROOT/remote"

cat > "$ROOT/etc/gcds.cnf" <<EOF
# 생성됨: tools/gen-conf.sh (직접 수정하지 말 것 - etc/site.conf를 고칠 것)
host.next.addr  = $NEXT_HOST
host.next.port  = $GCDS_PORT
host.next.token = $GCDS_TOKEN
host.next.map.1 = $NFS_EXPORT|$MOUNTPT
EOF

cat > "$ROOT/remote/gcdsd.cnf" <<EOF
# 생성됨: tools/gen-conf.sh (직접 수정하지 말 것 - etc/site.conf를 고칠 것)
port = $GCDS_PORT
token = $GCDS_TOKEN
tmpdir = /tmp
async = 0
allow = $NFS_SERVER
EOF

echo "gen-conf: etc/gcds.cnf, remote/gcdsd.cnf 생성 완료"
