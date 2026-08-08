#!/bin/bash
#
# Builds the Board Manager release: two tool archives, one platform archive, and
# the package index that points at them.
#
# Everything Board Manager needs is produced here. Upload the three archives to
# a GitHub release, then publish the generated index JSON at a stable URL -
# that URL is what students paste into the IDE.
#
# Usage: tools/make-release.sh <base-url> [version]
#   base-url  where the archives will be reachable, e.g.
#             https://github.com/you/flinduino-arm64/releases/download/v1.0.0
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="${1:?need the base URL the archives will be published under}"
VERSION="${2:-1.0.0}"
OUT="$HERE/release"
INDEX="$HERE/package_flinduino_arm64_index.json"
TC="$HERE/toolchain/mipsel-pic32-elf"

command -v shasum >/dev/null || { echo "shasum required" >&2; exit 1; }
[ -d "$TC" ] || { echo "no toolchain at $TC - run tools/setup-toolchain.sh" >&2; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT/stage"

# Arduino unpacks an archive and expects exactly one top-level directory; that
# directory becomes {runtime.tools.<name>.path}.
pack() {  # pack <staged-dir-name> <archive-name>
    local dir="$1" name="$2"
    ( cd "$OUT/stage" && tar czf "$OUT/$name" "$dir" )
    local sz sha
    sz=$(stat -f%z "$OUT/$name")
    sha=$(shasum -a 256 "$OUT/$name" | awk '{print $1}')
    echo "$name $sz $sha"
}

echo "==> staging toolchain"
cp -R "$TC" "$OUT/stage/mipsel-pic32-elf-10.2.0"
# Strip build noise; keeps the download reasonable for students on campus wifi.
find "$OUT/stage/mipsel-pic32-elf-10.2.0" -name '*.la' -delete 2>/dev/null || true
TC_INFO=$(pack mipsel-pic32-elf-10.2.0 "mipsel-pic32-elf-10.2.0-arm64-apple-darwin.tar.gz")

echo "==> staging pic32prog"
mkdir -p "$OUT/stage/pic32prog-2.1"
if [ -x "$HERE/prebuilt/pic32prog" ]; then
    cp "$HERE/prebuilt/pic32prog" "$OUT/stage/pic32prog-2.1/"
else
    echo "    error: no prebuilt/pic32prog - see tools/build-pic32prog.sh" >&2; exit 1
fi
PP_INFO=$(pack pic32prog-2.1 "pic32prog-2.1-arm64-apple-darwin.tar.gz")

echo "==> staging platform"
mkdir -p "$OUT/stage/pic32-$VERSION"
cp -R "$HERE/pic32/." "$OUT/stage/pic32-$VERSION/"
# platform.local.txt is a manual-install artefact and must not ship: it would
# override the Board Manager tool paths with paths from the packager's machine.
rm -f "$OUT/stage/pic32-$VERSION/platform.local.txt"
PL_INFO=$(pack "pic32-$VERSION" "flinduino-pic32-$VERSION.tar.gz")

rm -rf "$OUT/stage"

set -- $TC_INFO; TC_FILE=$1 TC_SIZE=$2 TC_SHA=$3
set -- $PP_INFO; PP_FILE=$1 PP_SIZE=$2 PP_SHA=$3
set -- $PL_INFO; PL_FILE=$1 PL_SIZE=$2 PL_SHA=$3

echo "==> writing package index"
cat > "$INDEX" <<JSON
{
  "packages": [
    {
      "name": "flinduino-arm64",
      "maintainer": "Flinduino Apple Silicon port",
      "websiteURL": "$BASE_URL",
      "email": "",
      "help": { "online": "$BASE_URL" },
      "platforms": [
        {
          "name": "Flinduino (arm64)",
          "architecture": "pic32",
          "version": "$VERSION",
          "category": "Contributed",
          "help": { "online": "$BASE_URL" },
          "url": "$BASE_URL/$PL_FILE",
          "archiveFileName": "$PL_FILE",
          "checksum": "SHA-256:$PL_SHA",
          "size": "$PL_SIZE",
          "boards": [
            { "name": "Flinduino" },
            { "name": "Flinduino Baseboard" }
          ],
          "toolsDependencies": [
            { "packager": "flinduino-arm64", "name": "mipsel-pic32-elf", "version": "10.2.0" },
            { "packager": "flinduino-arm64", "name": "pic32prog-arm64", "version": "2.1" }
          ]
        }
      ],
      "tools": [
        {
          "name": "mipsel-pic32-elf",
          "version": "10.2.0",
          "systems": [
            {
              "host": "arm64-apple-darwin",
              "url": "$BASE_URL/$TC_FILE",
              "archiveFileName": "$TC_FILE",
              "checksum": "SHA-256:$TC_SHA",
              "size": "$TC_SIZE"
            }
          ]
        },
        {
          "name": "pic32prog-arm64",
          "version": "2.1",
          "systems": [
            {
              "host": "arm64-apple-darwin",
              "url": "$BASE_URL/$PP_FILE",
              "archiveFileName": "$PP_FILE",
              "checksum": "SHA-256:$PP_SHA",
              "size": "$PP_SIZE"
            }
          ]
        }
      ]
    }
  ]
}
JSON

python3 -c "import json,sys; json.load(open('$INDEX')); print('    index is valid JSON')"

echo
echo "Release staged in $OUT:"
ls -lh "$OUT" | awk 'NR>1 {printf "  %-52s %s\n", $NF, $5}'
echo
echo "Next:"
echo "  1. Upload the three .tar.gz files to a release at $BASE_URL"
echo "  2. Commit package_flinduino_arm64_index.json - its raw URL is what students paste"
echo "  3. Students paste that URL into Preferences > Additional Board Manager URLs"
