# Shared settings, sourced by the other scripts. Override any of these from
# the environment; nothing here is specific to one machine.
#
#   WORK      where everything is cloned/built/downloaded (default: ~/wasm-rustc-build)
#   REPO      git URL of the compiler fork            (default: rad-rs/rust-wasm)
#   BRANCH    branch to build                         (default: wasm-host)
#   WASI_SDK_VERSION  wasi-sdk major version          (default: 24)
#   WASMTIME_VERSION  wasmtime used to run the compiler (default: v28.0.0; newer
#                     releases dropped the WASI threads support the compiler needs)
#   JOBS      parallel build jobs (default: 6; the build was tuned for ~15 GB RAM)
#   TARGET    Windows target the test/assemble scripts use: x86_64-pc-windows-gnu
#             (default) or i686-pc-windows-gnu

WORK="${WORK:-$HOME/wasm-rustc-build}"
REPO="${REPO:-https://github.com/rad-rs/rust-wasm.git}"
BRANCH="${BRANCH:-wasm-host}"
WASI_SDK_VERSION="${WASI_SDK_VERSION:-24}"
WASMTIME_VERSION="${WASMTIME_VERSION:-v28.0.0}"
JOBS="${JOBS:-6}"

RUST_SRC="$WORK/rust-wasm"
WASI_SDK="$WORK/wasi-sdk"
WASMTIME="${WASMTIME:-$WORK/wasmtime/wasmtime}"

# Build outputs.
RUSTC_WASM="$RUST_SRC/build/x86_64-unknown-linux-gnu/stage2-rustc/wasm32-wasip1-threads/release/rustc-main.wasm"

die() { echo "error: $*" >&2; exit 1; }

need() {
  for f in "$@"; do [ -e "$f" ] || die "missing $f (run scripts/build.sh first?)"; done
}

# select_target TRIPLE: sets TARGET, SYSROOT, WINLIB, MINGW_LIB and MINGW_GCC.
#
# The MinGW runtime comes from Debian's gcc-mingw-w64-x86-64 / -i686. Use the
# *-win32* gcc directory explicitly: a *-posix* one sits next to it and has
# different libgcc/libgcc_eh, so "the first match" is not safe.
#
# The standard library is looked up in the install tree (dist) first, then in
# the stage1 sysroot, where `x.py build --stage 1 library --target TRIPLE`
# leaves it (a target added after the last full install is only there).
select_target() {
  TARGET="$1"
  case "$TARGET" in
    x86_64-pc-windows-gnu) MINGW_PREFIX=x86_64-w64-mingw32 ;;
    i686-pc-windows-gnu)   MINGW_PREFIX=i686-w64-mingw32 ;;
    *) die "unsupported TARGET '$TARGET' (x86_64-pc-windows-gnu or i686-pc-windows-gnu)" ;;
  esac
  MINGW_LIB="/usr/$MINGW_PREFIX/lib"
  MINGW_GCC="$(ls -d "/usr/lib/gcc/$MINGW_PREFIX"/*-win32 2>/dev/null | head -1)"
  SYSROOT=""
  for s in "$RUST_SRC/dist" "$RUST_SRC/build/x86_64-unknown-linux-gnu/stage1"; do
    if [ -d "$s/lib/rustlib/$TARGET/lib" ]; then SYSROOT="$s"; break; fi
  done
  [ -n "$SYSROOT" ] || die "no $TARGET standard library under $RUST_SRC (run scripts/build.sh first?)"
  WINLIB="$SYSROOT/lib/rustlib/$TARGET/lib"
}

select_target "${TARGET:-x86_64-pc-windows-gnu}"
