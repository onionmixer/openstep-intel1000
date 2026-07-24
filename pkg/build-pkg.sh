#!/bin/sh
# build-pkg.sh -- build Pro1000.pkg, the OPENSTEP Installer package for the
# Intel 8254x gigabit DriverKit driver.
#
# Run this ON an OPENSTEP 4.2 machine (it uses /NextAdmin/Installer.app/package).
# It needs an already-built Pro1000.config bundle -- build one with:
#     ./tools/nx-install-driver.sh openstep-intel1000/Pro1000 -n
# which leaves it at /tmp/Pro1000/Pro1000.config on the target.
#
# Usage:  sh build-pkg.sh <path-to-Pro1000.config> [output-dir]
#
# Produces, in output-dir (default: current directory):
#   Pro1000.pkg       -- Installer package (double-click to install into
#                        /private/Devices; then activate with Configure)
#   Pro1000.pkg.tar   -- that bundle tarred for transport (uncompressed)
#
# Note: OPENSTEP has no `dirname`, so path parents are derived with sed.

set -e

CFG="${1:-Pro1000.config}"
OUT="${2:-.}"
PKGTOOL=/NextAdmin/Installer.app/package

# directory holding this script (where Pro1000.info lives)
case "$0" in
    */*) HERE=`echo "$0" | sed 's|/[^/]*$||'` ;;
    *)   HERE=. ;;
esac

if [ ! -d "$CFG" ]; then
    echo "build-pkg.sh: no such driver bundle: $CFG" >&2
    exit 1
fi
if [ ! -x "$PKGTOOL" ]; then
    echo "build-pkg.sh: $PKGTOOL not found (run on OPENSTEP)" >&2
    exit 1
fi

CFGNAME=`basename "$CFG"`
case "$CFG" in
    */*) CFGDIR=`echo "$CFG" | sed 's|/[^/]*$||'` ;;
    *)   CFGDIR=. ;;
esac

STAGE=/tmp/pro1000-pkgstage.$$
rm -rf "$STAGE" "$OUT/Pro1000.pkg" "$OUT/Pro1000.pkg.tar"
mkdir "$STAGE"

# stage the .config at the package root (installs as <DefaultLocation>/Pro1000.config)
( cd "$CFGDIR" && tar cf - "$CFGNAME" ) | ( cd "$STAGE" && tar xf - )

# build the package (no icon). stdin from /dev/null so it never blocks on a prompt.
"$PKGTOOL" -f "$STAGE" "$HERE/Pro1000.info" -d "$OUT" < /dev/null

rm -rf "$STAGE"

# tar the .pkg bundle (no gzip) for transport
( cd "$OUT" && tar cf Pro1000.pkg.tar Pro1000.pkg )

echo "built $OUT/Pro1000.pkg and $OUT/Pro1000.pkg.tar"
