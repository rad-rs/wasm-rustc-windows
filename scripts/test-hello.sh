#!/usr/bin/env bash
# Compile a hello-world for x86_64-pc-windows-gnu with the wasm-hosted rustc,
# running under wasmtime, and check that the result is a PE32+ executable.
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
  --target x86_64-pc-windows-gnu --sysroot /sysroot \
  --color never --error-format short \
  -C linker-flavor=ld.lld -C link-arg=/mingw/crt2.o -C link-arg=-L/mingw \
  -o /work/hello.exe

file "$T/work/hello.exe" | tee "$T/file.txt"
grep -q 'PE32+ executable' "$T/file.txt" && echo "OK: $T/work/hello.exe"
