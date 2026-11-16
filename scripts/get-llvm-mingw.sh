#!/usr/bin/env bash
# Download llvm-mingw (https://github.com/mstorsjo/llvm-mingw) into $LLVM_MINGW.
# Needed for the three *-windows-gnullvm targets (x86_64, i686, aarch64): it
# provides their MinGW runtime (crt2.o, import libraries, libunwind) and the clang
# wrappers bootstrap uses to build the standard library's C parts. We use the UCRT
# flavour, so executables built for those targets need Windows 10 or later. llvm-mingw is MIT-licensed
# (its bundled LLVM and mingw-w64 components have their own licences, see
# LICENSE.TXT inside the archive); nothing from it is redistributed by this repo.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$here/env.sh"
if [ -x "$LLVM_MINGW/bin/aarch64-w64-mingw32-clang" ]; then echo "already have llvm-mingw in $LLVM_MINGW"; exit 0; fi
mkdir -p "$WORK"
name="llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-22.04-x86_64"
url="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${name}.tar.xz"
tmp="$(mktemp -d)"
curl -fsSL "$url" | tar -xJ -C "$tmp"
rm -rf "$LLVM_MINGW"
mv "$tmp/$name" "$LLVM_MINGW"
rmdir "$tmp"
"$LLVM_MINGW/bin/aarch64-w64-mingw32-clang" --version | head -1
