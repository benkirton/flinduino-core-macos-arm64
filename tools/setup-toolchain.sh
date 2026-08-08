#!/bin/bash
#
# Builds the native arm64 PIC32 toolchain this platform needs.
#
# Downloads Majenko's mipsel-pic32-elf GCC 10.2 for Apple Silicon, regenerates
# the PIC32 support files from a patched pic32-genfiles, and applies the three
# toolchain-level fixes described in PORTING.md.
#
# Idempotent: safe to re-run. Docker is used only to run the generator (which is
# PHP) against a Linux copy of the toolchain, so nothing is installed on the Mac
# outside the target directory.
#
# Usage: tools/setup-toolchain.sh [install-dir]
#        default install-dir is ./toolchain
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$HERE/toolchain}"
TC_URL="https://github.com/MajenkoProjects/chipkit-compiler/releases/download/v0.0.1/mipsel-pic32-elf_10.2.0_arm64e-apple-darwin20.tar.bz2"
GENFILES_REPO="https://github.com/MajenkoProjects/pic32-genfiles.git"
WORK="$DEST/.build"

command -v docker >/dev/null || { echo "error: docker is required (used only to run the PHP generator)" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "error: docker daemon is not running" >&2; exit 1; }

mkdir -p "$WORK"

# ---------------------------------------------------------------- toolchain
if [ ! -x "$DEST/mipsel-pic32-elf/bin/mipsel-pic32-elf-gcc" ]; then
    echo "==> downloading mipsel-pic32-elf 10.2.0 (arm64e)"
    curl -fL --progress-bar -o "$WORK/tc.tar.bz2" "$TC_URL"
    mkdir -p "$DEST"
    tar xjf "$WORK/tc.tar.bz2" -C "$DEST"
    chmod -R u+w "$DEST/mipsel-pic32-elf"
else
    echo "==> toolchain already present"
fi
TC="$DEST/mipsel-pic32-elf/mipsel-pic32-elf"

# ---------------------------------------------------------------- generator
if [ ! -d "$WORK/pic32-genfiles" ]; then
    echo "==> cloning pic32-genfiles"
    git clone --quiet "$GENFILES_REPO" "$WORK/pic32-genfiles"
fi

echo "==> applying pic32-genfiles fixes"
(
    cd "$WORK/pic32-genfiles"
    git checkout --quiet -- . 2>/dev/null || true
    git apply "$HERE/patches/pic32-genfiles/0001-fix-generated-sfr-addresses-and-bitfield-order.patch"
)

# The generator is PHP and shells out to mipsel-pic32-elf-gcc. Run both in a
# container against the native arm64 Linux build of the same toolchain: the
# output is MIPS archives and headers, so it is host-independent.
echo "==> building generator image"
docker build -q -t pic32-genfiles-runner - >/dev/null <<'DOCKERFILE'
FROM php:8-cli
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates bzip2 make \
    && rm -rf /var/lib/apt/lists/*
ARG TC=https://github.com/MajenkoProjects/chipkit-compiler/releases/download/v0.0.1/mipsel-pic32-elf_10.2.0_aarch64-linux-gnu.tar.bz2
RUN curl -fsSL -o /tmp/tc.tar.bz2 "$TC" && mkdir -p /opt && tar xjf /tmp/tc.tar.bz2 -C /opt && rm /tmp/tc.tar.bz2
ENV PATH=/opt/mipsel-pic32-elf/bin:$PATH
WORKDIR /src
DOCKERFILE

echo "==> generating PIC32 support files (takes a few minutes)"
docker run --rm -v "$WORK/pic32-genfiles:/src" pic32-genfiles-runner php bin/pic32-genfiles >"$WORK/genfiles.log" 2>&1 \
    || { echo "generation failed, see $WORK/genfiles.log" >&2; exit 1; }

echo "==> installing generated headers and libraries"
chmod -R u+w "$TC"
cp -R "$WORK/pic32-genfiles/lib" "$WORK/pic32-genfiles/include" "$TC/"
cp "$WORK/pic32-genfiles/src/cp0defs.h" "$TC/include/"
cp "$WORK/pic32-genfiles/ld/mips-chipKIT-application-COMMON.ld" "$TC/lib/proc/"

# ------------------------------------------------- toolchain-level fixes
# 1. sys/attribs.h - the core includes it for ISR attribute macros, and the
#    mainline toolchain has no equivalent.
echo "==> installing sys/attribs.h"
mkdir -p "$TC/include/sys"
cp "$HERE/patches/toolchain/sys-attribs.h" "$TC/include/sys/attribs.h"

# 2. The .bss fix in Majenko's linker script. Applied here rather than as a
#    patch file because the upstream file has CRLF line endings, which makes a
#    unified diff useless.
echo "==> patching mips-chipKIT-application-COMMON.ld"
python3 - "$TC/lib/proc/mips-chipKIT-application-COMMON.ld" <<'PY'
import sys
p = sys.argv[1]
data = open(p, 'rb').read()
old = b"*(.dynbss)\r\n    *(.gnu.linkonce.b.*)"
new = (b"*(.dynbss)\r\n"
       b"    /* Added: the .bss output section never collected .bss inputs, so with\r\n"
       b"       -fdata-sections every bss chunk orphaned into loadable flash instead\r\n"
       b"       of becoming NOBITS in RAM, and was never zeroed. Do NOT also fold\r\n"
       b"       .sdata/.sbss in here - they are gp-addressed and moving them\r\n"
       b"       overflows R_MIPS_GPREL16. */\r\n"
       b"    *(.bss .bss.*)\r\n"
       b"    *(.gnu.linkonce.b.*)")
if b"*(.bss .bss.*)" in data:
    print("    already patched")
elif old in data:
    open(p, 'wb').write(data.replace(old, new, 1))
    print("    patched")
else:
    sys.exit("    ERROR: anchor not found in COMMON.ld")
PY

# 3. genfiles' runtime redefines 23 symbols that newlib and libstdc++ already
#    provide. Weaken them so the standard definitions win, rather than reaching
#    for --allow-multiple-definition which would hide genuine clashes.
echo "==> weakening duplicate symbols in lib32*.a"
NM="$DEST/mipsel-pic32-elf/bin/mipsel-pic32-elf-nm"
OBJCOPY="$DEST/mipsel-pic32-elf/bin/mipsel-pic32-elf-objcopy"
STD=$(mktemp); GEN=$(mktemp)
for lib in "$TC/lib/soft-float/libc.a" "$TC/lib/soft-float/libstdc++.a" \
           "$DEST/mipsel-pic32-elf/lib/gcc/mipsel-pic32-elf/10.2.0/soft-float/libgcc.a"; do
    [ -f "$lib" ] && "$NM" --defined-only "$lib" 2>/dev/null | awk '$2 ~ /^[TDBRW]$/ {print $3}'
done | sort -u > "$STD"
for lib in "$TC"/lib/proc/lib32*.a; do
    "$NM" --defined-only "$lib" 2>/dev/null | awk '{print $3}' | grep -v '^$' | sort -u > "$GEN"
    args=(); while read -r s; do args+=(--weaken-symbol="$s"); done < <(comm -12 "$GEN" "$STD")
    if [ ${#args[@]} -gt 0 ]; then
        "$OBJCOPY" "${args[@]}" "$lib" "$lib.tmp" && mv "$lib.tmp" "$lib"
    fi
done
rm -f "$STD" "$GEN"

# ---------------------------------------------------------------- verify
echo "==> verifying"
"$DEST/mipsel-pic32-elf/bin/mipsel-pic32-elf-gcc" --version | head -1
test -f "$TC/lib/proc/32mx250f128d-app.ld"  || { echo "missing per-chip linker script" >&2; exit 1; }
test -f "$TC/include/proc/p32mx250f128d.h"  || { echo "missing proc header" >&2; exit 1; }
echo
echo "Toolchain ready: $DEST/mipsel-pic32-elf"
echo "Point platform.txt at it, or run: bin/flinduino doctor"
