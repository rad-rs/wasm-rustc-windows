#!/usr/bin/env bash
# Assemble the directory the RAD designer's native .exe pipeline downloads
# (crates/rad-designer/native-toolchain/ in https://github.com/rad-rs/rad;
# see native-build-pipeline.js there) from a finished build of this recipe.
#
#   scripts/assemble-designer-toolchain.sh DEST [TRIPLE...]
#
# TRIPLE defaults to x86_64-pc-windows-gnu and i686-pc-windows-gnu (the two that
# need only apt packages); name aarch64-pc-windows-gnullvm explicitly to add ARM64
# (it also needs scripts/get-llvm-mingw.sh and a stage1 standard library for it).
#
# Layout produced:
#   rustc_opt.wasm            the compiler (rustc-main.wasm; shared by all targets;
#                             the name is what the pipeline fetches)
#   <triple>/crt2.o           MinGW-w64 C runtime start-up object for that target
#   <triple>/mingw-libs/*.a   import libraries + libgcc (libunwind for gnullvm), plus
#                             index.json (JSON array of stems)
#   <triple>/sysroot/*.rlib *.rmeta
#                             that target's standard library, rustc's "-<hash>"
#                             filename suffix stripped (the .rmeta files are
#                             required: the rlibs alone are metadata stubs)
#   <triple>/sysroot/rsbegin.o rsend.o   (not for gnullvm: that target does not use them)
#   <triple>/sysroot/index.json   JSON array of rlib stems
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$here/env.sh"
DEST="${1:?usage: assemble-designer-toolchain.sh DEST [TRIPLE...]}"
shift
TRIPLES=("$@")
[ "${#TRIPLES[@]}" -gt 0 ] || TRIPLES=(x86_64-pc-windows-gnu i686-pc-windows-gnu)
need "$RUSTC_WASM"

# Import libraries the pipeline mounts at /mingw-libs.
MINGW_LIBS_GNU="advapi32 bcrypt comctl32 dbghelp gdi32 kernel32 mingw32 mingwex msvcrt ntdll pthread synchronization user32 userenv winpthread ws2_32"
# ARM64 (llvm-mingw, UCRT): found by linking the all-controls demo with a trimmed
# library directory and adding whatever lld reported missing. libmsvcrt.a is the
# UCRT import library there (same size as libucrt.a), and unwinding is libunwind
# (the target's link args add -l:libunwind.a), not libgcc_eh.
MINGW_LIBS_LLVM="advapi32 bcrypt comctl32 dbghelp gdi32 kernel32 mingw32 mingwex msvcrt ntdll synchronization unwind user32 userenv ws2_32"

# JSON array of the names given on stdin, one per line: ["a", "b"]
json_array() { sed 's/.*/"&"/' | paste -sd, - | sed 's/,/, /g; s/^/[/; s/$/]/'; }

rm -rf "$DEST"
mkdir -p "$DEST"
cp "$RUSTC_WASM" "$DEST/rustc_opt.wasm"

for triple in "${TRIPLES[@]}"; do
  select_target "$triple"
  need "$WINLIB" "$MINGW_LIB/crt2.o"
  [ -z "$MINGW_GCC" ] || need "$MINGW_GCC/libgcc.a"
  out="$DEST/$triple"
  mkdir -p "$out/sysroot" "$out/mingw-libs"

  cp "$MINGW_LIB/crt2.o" "$out/crt2.o"

  if [ -n "$MINGW_GCC" ]; then libs="$MINGW_LIBS_GNU"; else libs="$MINGW_LIBS_LLVM"; fi
  for l in $libs; do
    cp "$MINGW_LIB/lib$l.a" "$out/mingw-libs/lib$l.a"
  done
  [ -z "$MINGW_GCC" ] || cp "$MINGW_GCC/libgcc.a" "$MINGW_GCC/libgcc_eh.a" "$out/mingw-libs/"
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
