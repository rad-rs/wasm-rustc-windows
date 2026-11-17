#!/usr/bin/env bash
# Clone and build the wasm-hosted rustc (rad-rs/rust-wasi, branch wasm-host).
#
#   scripts/build.sh          clone (if needed), configure, build + install
#   scripts/build.sh config   only print the generated bootstrap.toml
#
# This is a long build (hours the first time; the wasm LLVM alone took ~19
# minutes at -j6, and later rustc rebuilds ~10-14 minutes). It needs the
# packages listed in the README. It is safe to re-run: clones and downloads
# are skipped when present. After a FAILED LLVM build, delete
# $WORK/rust-wasi/build/wasm32-wasip1-threads/llvm before re-running (see
# "Gotchas" in the README).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$here/env.sh"

gen_config() {
  sed -e "s|@WASI_SDK@|$WASI_SDK|g" -e "s|@LLVM_MINGW@|$LLVM_MINGW|g" "$here/../config/bootstrap.toml.in"
}

if [ "${1:-}" = "config" ]; then gen_config; exit 0; fi

mkdir -p "$WORK"

# Rust toolchain used to run bootstrap (stage0 is downloaded by x.py itself).
if ! command -v cargo >/dev/null 2>&1; then
  [ -f "$HOME/.cargo/env" ] || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
fi
# shellcheck disable=SC1091
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# wasi-sdk
if [ ! -x "$WASI_SDK/bin/clang" ]; then
  url="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/wasi-sdk-${WASI_SDK_VERSION}.0-x86_64-linux.tar.gz"
  tmp="$(mktemp -d)"
  curl -fsSL "$url" | tar -xz -C "$tmp"
  rm -rf "$WASI_SDK"
  mv "$tmp"/wasi-sdk-* "$WASI_SDK"
  rmdir "$tmp"
fi

# llvm-mingw: the ARM64 target's MinGW runtime and C compiler.
"$here/get-llvm-mingw.sh"

# Source. The LLVM submodule (rad-rs/rust-llvm-wasi, branch wasi-host/23.1)
# carries the WASI-host patches; .gitmodules in the branch already points there.
if [ ! -d "$RUST_SRC/.git" ]; then
  git clone --filter=blob:none --single-branch --branch "$BRANCH" "$REPO" "$RUST_SRC"
fi
git -C "$RUST_SRC" checkout -q "$BRANCH"
git -C "$RUST_SRC" submodule update --init --depth 1 src/llvm-project

# Config (gitignored by the rust repo, so it never dirties the tree).
gen_config > "$RUST_SRC/bootstrap.toml"

export WASI_SDK_PATH="$WASI_SDK"
export WASI_SYSROOT="$WASI_SDK/share/wasi-sysroot"   # without this the link picks the non-threads libc
export CC=gcc CXX=g++
ulimit -s 1048576 || true                            # 1 GB; "unlimited" gave one intermittent clang segfault on a predecessor build
cd "$RUST_SRC"
./x.py install -j"$JOBS" --config bootstrap.toml

echo
echo "compiler : $RUSTC_WASM"
echo "sysroot  : $SYSROOT"
