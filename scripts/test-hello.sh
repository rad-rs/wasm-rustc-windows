#!/usr/bin/env bash
# Compile a hello-world for a Windows target with the wasm-hosted rustc,
# running under wasmtime, and check the result is a PE executable.
#
#   scripts/test-hello.sh                                     # x64 (PE32+), the default
#   TARGET=i686-pc-windows-gnullvm scripts/test-hello.sh      # x86 (PE32)
#   TARGET=aarch64-pc-windows-gnullvm scripts/test-hello.sh   # ARM64
# (needs scripts/get-llvm-mingw.sh first)
# The produced exe is $WORK/test-hello/work/hello.exe (copy it to Windows to run it;
# the ARM64 one needs ARM64 Windows hardware, so for that target this script only
# checks that it links and has a well-formed ARM64 PE header).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$here/env.sh"
need_std
need "$RUSTC_WASM" "$WINLIB" "$WASMTIME" "$MINGW_LIB/crt2.o"

T="$WORK/test-hello"
rm -rf "$T"; mkdir -p "$T/work" "$T/mingw"
cp "$MINGW_LIB"/*.a "$MINGW_LIB/crt2.o" "$T/mingw/"
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

check_pe "$T/work/hello.exe" console
