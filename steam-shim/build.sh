#!/bin/bash
# Build the steam.exe shim from the tracked sources in this directory.
#
# The shim is a PE executable and the wine build tree's own make builds it, so
# unlike the lsteamclient unix half there is no hand-rolled compile or link here.
#
# Only x86_64 is built and shipped. The tree can produce an i386 shim as well and
# nothing consumes it: RUN_SCRIPT stages one flat steam.exe into the prefix Steam
# directory, and a 32 bit game reaching it gets a separate process under wow64, so
# the 64 bit build serves both.
#
# A rebuild from unchanged source is byte-identical except for TimeDateStamp and
# the optional header CheckSum, so the hash reported below has those two fields
# zeroed and is comparable across builds. See pe-info.py.
#
# Usage:
#   ./build.sh              build and verify
#   ./build.sh --install    also install to the bridge
#
# Overridable: WINE_BUILD, WINE_SRC_REL, BRIDGE_DIR

set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)

WINE_BUILD=${WINE_BUILD:-$repo/scratch/wine-build-dual}
# Relative because it lands in the debug info. Keep the default sibling layout so
# a rebuild stays comparable to the shipped binary.
WINE_SRC_REL=${WINE_SRC_REL:-../wine}
BRIDGE_DIR=${BRIDGE_DIR:-$HOME/Library/Application Support/protonish/bridge}

install=0
[ "${1:-}" = "--install" ] && install=1

prog=programs/steam.exe
out=$prog/x86_64-windows/steam.exe

if [ ! -d "$WINE_BUILD/$prog" ]; then
	echo "==> no wine build tree at $WINE_BUILD/$prog"
	echo "    run bridge/setup-wine-tree.sh to clone and configure it"
	exit 1
fi

cd "$WINE_BUILD"

src=$WINE_SRC_REL/$prog
[ -d "$src" ] || { echo "==> no wine source tree at $WINE_BUILD/$src"; exit 1; }

command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "==> missing x86_64-w64-mingw32-gcc, install mingw-w64"; exit 1; }

"$here/fetch-headers.sh"

echo "==> syncing tracked sources into $WINE_SRC_REL/$prog"
# The generated Makefile lists only config.status and makedep as its prerequisites,
# not the per-module Makefile.in files, so a change to IMPORTS or EXTRAINCL here is
# silently ignored and the build keeps using the previous flags. Notice it rather
# than trusting make to.
regen=0
cmp -s "$here/Makefile.in" "$src/Makefile.in" || regen=1

# Unchanged files keep their mtime so make does not rebuild what it does not have
# to. proton-headers/ goes across too: it is generated, but EXTRAINCL is written
# against srcdir, so it has to sit under it.
rsync -a --exclude build.sh --exclude fetch-headers.sh "$here/" "$src/"

if [ "$regen" = 1 ]; then
	echo "==> Makefile.in changed, regenerating the build Makefile"
	./config.status Makefile >/dev/null
fi

echo "==> building $out"
make "$out" >/dev/null

size=$(stat -f %z "$out")
# shellcheck disable=SC2046
set -- $("$here/../bridge/pe-info.py" "$out")
[ "$1" = "x86_64" ] || { echo "==> built $1, expected x86_64"; exit 1; }
# The shim statically links jsoncpp and weighs ~14 MB. Anything near zero means
# the link dropped objects.
[ "$size" -gt 1000000 ] || { echo "==> only $size bytes, the link dropped objects"; exit 1; }
if grep -qa 'ole32\.dll' "$out"; then
	echo "==> the shim imports ole32, so a helper run would show up in the Dock"
	exit 1
fi
echo "==> built $out  $1  $size bytes  $2 (timestamp and checksum zeroed)"

[ "$install" -eq 1 ] || { echo "==> not installing, pass --install to deploy"; exit 0; }

# One consumer: RUN_SCRIPT copies the flat bridge copy into the prefix Steam
# directory on every launch. The shim is not a wine builtin, so nothing goes into
# the CrossOver tree.
dst=$BRIDGE_DIR/steam.exe
mkdir -p "$BRIDGE_DIR"
cp -f "$out" "$dst"
cmp -s "$out" "$dst" || { echo "==> install verify failed: $dst differs from $out"; exit 1; }
echo "==> installed $dst"
echo "==> done. prefixes refresh their copy from the bridge on next launch."
