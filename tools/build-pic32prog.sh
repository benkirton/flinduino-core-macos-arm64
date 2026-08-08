#!/bin/bash
#
# Builds a native arm64 pic32prog from source into prebuilt/.
#
# The uploader shipped with the Flinders package is an i386+x86_64 fat binary,
# so it needs Rosetta. Majenko's fork builds cleanly on arm64 and links only
# system frameworks, which makes the whole toolchain Rosetta-free.
#
# Majenko's fork specifically, not upstream sergev/pic32prog: upstream 2.0.1 has
# no -R flag, and both platform.txt and bin/flinduino rely on it to wait for the
# board to re-enumerate.
#
# Build-time dependencies (not needed by students, only to produce the binary):
#   brew install autoconf automake pkg-config
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${TMPDIR:-/tmp}/pic32prog-mj"
REPO="https://github.com/majenkotech/pic32prog-autotools.git"

for t in autoreconf automake pkg-config git; do
    command -v "$t" >/dev/null || { echo "error: $t missing - brew install autoconf automake pkg-config" >&2; exit 1; }
done

[ -d "$SRC" ] || git clone --quiet --depth 1 "$REPO" "$SRC"

cd "$SRC"
echo "==> configuring"
# -if, not -i: the tree ships pre-generated autotools files that are older than
# current autoconf, and without --force autopoint refuses to overwrite them.
autoreconf -if >/dev/null 2>&1
./configure >/dev/null
echo "==> building"
make >/dev/null

BIN="$SRC/src/pic32prog"
[ -x "$BIN" ] || { echo "error: build produced no binary" >&2; exit 1; }

arch=$(file -b "$BIN")
case "$arch" in
    *arm64*) ;;
    *) echo "error: built $arch, expected arm64" >&2; exit 1 ;;
esac

# Confirm the flag the platform depends on actually exists in this build.
"$BIN" --help 2>&1 | grep -q '^\s*-R,' || { echo "error: this build has no -R flag" >&2; exit 1; }

mkdir -p "$HERE/prebuilt"
cp "$BIN" "$HERE/prebuilt/pic32prog"
# arm64 binaries must be signed to run; ad-hoc is enough for local distribution.
codesign --force -s - "$HERE/prebuilt/pic32prog"

echo
echo "prebuilt/pic32prog  $(file -b "$HERE/prebuilt/pic32prog")"
echo "linked against:"
otool -L "$HERE/prebuilt/pic32prog" | tail -n +2 | awk '{print "  "$1}'
