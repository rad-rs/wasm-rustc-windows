#!/usr/bin/env bash
# Assemble the directory the RAD designer's native .exe pipeline downloads
# (crates/rad-designer/native-toolchain/ in https://github.com/rad-rs/rad;
# see native-build-pipeline.js there) from a finished build of this recipe.
#
#   scripts/assemble-designer-toolchain.sh DEST [TRIPLE...]
#
# TRIPLE defaults to all three: x86_64-pc-windows-gnullvm, i686-pc-windows-gnullvm
# and aarch64-pc-windows-gnullvm. They need scripts/get-llvm-mingw.sh, and every
# target needs its standard library built (one x.py invocation with a comma-separated --target
# list for all of them; see the README).
#
# Layout produced:
#   rustc_opt.wasm            the compiler (rustc-main.wasm; shared by all targets;
#                             the name is what the pipeline fetches)
#   <triple>/crt2.o           MinGW-w64 C runtime start-up object for that target
#   <triple>/mingw-libs/*.a   import libraries + libunwind, plus
#                             index.json (JSON array of stems)
#   <triple>/sysroot/*.rlib *.rmeta
#                             that target's standard library, rustc's "-<hash>"
#                             filename suffix stripped (the .rmeta files are
#                             required: the rlibs alone are metadata stubs)
#   <triple>/sysroot/index.json   JSON array of rlib stems
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$here/env.sh"
DEST="${1:?usage: assemble-designer-toolchain.sh DEST [TRIPLE...]}"
shift
TRIPLES=("$@")
[ "${#TRIPLES[@]}" -gt 0 ] || TRIPLES=(x86_64-pc-windows-gnullvm i686-pc-windows-gnullvm aarch64-pc-windows-gnullvm)
need "$RUSTC_WASM"

# Import libraries the pipeline mounts at /mingw-libs (llvm-mingw, UCRT): found by
# linking the all-controls demo with a trimmed library directory and adding whatever
# lld reported missing. libmsvcrt.a is the UCRT import library there (same size as
# libucrt.a), and unwinding is libunwind (the target's link args add -l:libunwind.a).
MINGW_LIBS="advapi32 bcrypt comctl32 dbghelp gdi32 kernel32 mingw32 mingwex msvcrt ntdll synchronization unwind user32 userenv ws2_32"

# JSON array of the names given on stdin, one per line: ["a", "b"]
json_array() { sed 's/.*/"&"/' | paste -sd, - | sed 's/,/, /g; s/^/[/; s/$/]/'; }

rm -rf "$DEST"
mkdir -p "$DEST"
cp "$RUSTC_WASM" "$DEST/rustc_opt.wasm"

for triple in "${TRIPLES[@]}"; do
  select_target "$triple"
  need_std
  need "$WINLIB" "$MINGW_LIB/crt2.o"
  out="$DEST/$triple"
  mkdir -p "$out/sysroot" "$out/mingw-libs"

  cp "$MINGW_LIB/crt2.o" "$out/crt2.o"

  for l in $MINGW_LIBS; do
    cp "$MINGW_LIB/lib$l.a" "$out/mingw-libs/lib$l.a"
  done
  ( cd "$out/mingw-libs" && ls ./*.a | sed 's|^\./||; s|\.a$||' | LC_ALL=C sort | json_array > index.json )

  for f in "$WINLIB"/*.rlib "$WINLIB"/*.rmeta; do
    b="$(basename "$f")"
    cp "$f" "$out/sysroot/$(printf '%s' "$b" | sed -E 's/-[0-9a-f]{16}\.(rlib|rmeta)$/.\1/')"
  done
  [ "$RS_OBJECTS" = 0 ] || cp "$WINLIB/rsbegin.o" "$WINLIB/rsend.o" "$out/sysroot/"
  ( cd "$out/sysroot" && ls ./*.rlib | sed 's|^\./||; s|\.rlib$||' | LC_ALL=C sort | json_array > index.json )
  echo "  $triple: $(ls "$out/sysroot" | wc -l) sysroot files, $(ls "$out/mingw-libs" | wc -l) mingw-libs files"
done

echo "assembled $DEST"
du -sh "$DEST"
