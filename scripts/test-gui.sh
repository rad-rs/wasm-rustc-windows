#!/usr/bin/env bash
# Build the rad demo form (crates/rad-demo + rad-core + rad-backend-win32 from
# https://github.com/rad-rs/rad) into a Windows GUI exe with the wasm-hosted
# rustc, mounting the sources as sibling modules of one crate exactly as the
# designer's in-browser pipeline does.
#
#   RAD_CRATES=/path/to/rad/crates scripts/test-gui.sh
#   TARGET=i686-pc-windows-gnullvm RAD_CRATES=... scripts/test-gui.sh   # x86 (x64 is the default)
#   TARGET=aarch64-pc-windows-gnullvm RAD_CRATES=... scripts/test-gui.sh   # ARM64 (link + header check only)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$here/env.sh"
need_std
CR="${RAD_CRATES:?set RAD_CRATES to the crates/ directory of a rad-rs/rad checkout}"
need "$RUSTC_WASM" "$WINLIB" "$WASMTIME" "$CR/rad-core/src/lib.rs" "$CR/rad-demo/src/form1.rs" "$MINGW_LIB/crt2.o"

T="$WORK/test-gui"
rm -rf "$T"; mkdir -p "$T/app/rad_core" "$T/mingw"
cp "$MINGW_LIB"/*.a "$MINGW_LIB/crt2.o" "$T/mingw/"

# Mount tree: rad_core.rs + rad_core/*.rs ("crate::" gains one segment as a
# submodule), the Win32 backend and the form as siblings of main.rs.
cp "$CR/rad-core/src/lib.rs" "$T/app/rad_core.rs"
for f in "$CR"/rad-core/src/*.rs; do
  b="$(basename "$f")"
  [ "$b" = lib.rs ] && continue
  sed 's/crate::/crate::rad_core::/g' "$f" > "$T/app/rad_core/$b"
done
sed 's/rad_core::/crate::rad_core::/g' "$CR/rad-backend-win32/src/lib.rs"   > "$T/app/rad_backend_win32.rs"
sed 's/rad_core::/crate::rad_core::/g' "$CR/rad-demo/src/form1.rs"          > "$T/app/form1.rs"
sed 's/rad_core::/crate::rad_core::/g' "$CR/rad-demo/src/form1.designer.rs" > "$T/app/form1.designer.rs"
cp "$here/../config/gui-main.rs" "$T/app/main.rs"

"$WASMTIME" run -Sthreads=y -Spreview2=n \
  --dir "$T/app::/work" --dir "$SYSROOT::/sysroot" --dir "$T/mingw::/mingw" \
  --env RUST_MIN_STACK=16777216 --env RUSTC_BOOTSTRAP=1 \
  "$RUSTC_WASM" /work/main.rs --crate-name app --crate-type bin --edition 2021 \
  --target "$TARGET" --sysroot /sysroot \
  --color never --error-format short \
  -C linker-flavor=ld.lld -C link-arg=/mingw/crt2.o -C link-arg=-L/mingw \
  -C link-arg=--subsystem=windows -o /work/out.exe

check_pe "$T/app/out.exe" GUI
