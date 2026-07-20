#!/bin/bash
# make-dist.sh - build dist/openstep-intel1000-src.tar
#
# Everything an OPENSTEP machine needs to build the driver, and nothing
# from this repository's host-side tooling. Plain tar, no gzip: the tar
# on these machines is old, and 150 KB is not worth a compatibility
# question.
#
# Path length matters. NeXT's tar is a v7-style archiver with a 100-byte
# name field, so this checks before writing rather than producing an
# archive that silently truncates.
set -eu
cd "$(dirname "$0")/.."

OUT=dist/openstep-intel1000-src.tar
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

D=$STAGE/openstep-intel1000
mkdir -p "$D"

# the driver bundle, minus build products
cp -r Pro1000 "$D/"
rm -rf "$D/Pro1000/Pro1000.config" "$D/Pro1000/obj" "$D/Pro1000"/*/obj

# finding your card, and measuring the result
cp -r pcils "$D/"
rm -rf "$D/pcils/PCIscan/PCIscan.config" "$D/pcils/PCIscan/obj" \
       "$D/pcils/PCIscan"/*/obj "$D/pcils/pcils"
# scan output from the development machine - an example, not a deliverable
rm -f "$D/pcils"/scan-*.txt
cp perf/nxperf.c "$D/"

# the documentation, which is the same README the repository carries
cp README.md "$D/"
cp Configure_APP_SCREENSHOT.png "$D/"

long=$(cd "$STAGE" && find . -printf '%p\n' | awk 'length($0) > 100')
if [ -n "$long" ]; then
    echo "make-dist: paths over 100 bytes, NeXT tar would truncate:" >&2
    echo "$long" >&2
    exit 1
fi

mkdir -p dist
(cd "$D" && tar cf - .) > "$OUT"

echo "$OUT"
(cd "$STAGE" && find . -printf '%p\n' | awk '{ if (length($0) > m) m = length($0) } END { print "  longest path: " m " bytes" }')
ls -l "$OUT" | awk '{ printf "  %d bytes\n", $5 }'
