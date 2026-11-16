#!/usr/bin/env bash
# Compile a hello-world for a Windows target with the wasm-hosted rustc,
# running under wasmtime, and check the result is a PE executable.
#
#   scripts/test-hello.sh                              # 64-bit (PE32+)
#   TARGET=i686-pc-windows-gnu scripts/test-hello.sh   # 32-bit (PE32)
# The produced exe is $WORK/test-hello/work/hello.exe (copy it to Windows to run it).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$here/env.sh"
need "$RUSTC_WASM" "$WINLIB" "$WASMTIME" "$MINGW_LIB/crt2.o" "$MINGW_GCC/libgcc_eh.a"

T="$WORK/test-hello"
rm -rf "$T"; mkdir -p "$T/work" "$T/mingw"
cp "$MINGW_LIB"/*.a "$MINGW_LIB/crt2.o" "$MINGW_GCC"/*.a "$T/mingw/"
echo 'fn main() { println!("Hello from the wasm-hosted rustc!"); }' > "$T/work/hello.rs"

# --dir mounts: the work dir, the sysroot (dist) and the MinGW runtime.
# Default compiler flags: no -Zthreads needed.
"$WASMTIME" run -Sthreads=y -Spreview2=n \
  --dir "$T/work::/work" --dir "$SYSROOT::/sysroot" --dir "$T/mingw::/mingw" \
  --env RUST_MIN_STACK=16777216 --env RUSTC_BOOTSTRAP=1 \
  "$RUSTC_WASM" /work/hello.rs --crate-name hello --edition 2021 \
  --target "$TARGET" --sysroot /sysroot \
  --color never --error-format short \
  -C linker-flavor=ld.lld -C link-arg=/mingw/crt2.o -C link-arg=-L/mingw \
  -o /work/hello.exe

file "$T/work/hello.exe" | tee "$T/file.txt"
case "$TARGET" in i686*) want='PE32 executable' ;; *) want='PE32+ executable' ;; esac
grep -q "$want" "$T/file.txt" && echo "OK: $T/work/hello.exe"
