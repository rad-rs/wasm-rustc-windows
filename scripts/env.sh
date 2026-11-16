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
SYSROOT="$RUST_SRC/dist"
WINLIB="$SYSROOT/lib/rustlib/x86_64-pc-windows-gnu/lib"

# MinGW runtime, from Debian's gcc-mingw-w64-x86-64. Use the *-win32* gcc
# directory explicitly: a *-posix* one sits next to it and has different
# libgcc/libgcc_eh, so "the first match" is not safe.
MINGW_LIB="${MINGW_LIB:-/usr/x86_64-w64-mingw32/lib}"
MINGW_GCC="${MINGW_GCC:-$(ls -d /usr/lib/gcc/x86_64-w64-mingw32/*-win32 2>/dev/null | head -1)}"

die() { echo "error: $*" >&2; exit 1; }

need() {
  for f in "$@"; do [ -e "$f" ] || die "missing $f (run scripts/build.sh first?)"; done
}
