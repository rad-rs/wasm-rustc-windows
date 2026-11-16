#!/bin/bash
# Build bjorn3/rust compile_rustc_for_wasm17 + MinGW LLD driver patch -> rustc.wasm
# Adapted from .research/spike-exe/docker-build/build.sh. Runs as a normal user in WSL.
set -ex

export DEBIAN_FRONTEND=noninteractive
JOBS="${JOBS:-8}"

if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
fi
source "$HOME/.cargo/env"

mkdir -p "$HOME/build"
cd "$HOME/build"

if [ ! -d wasi-sdk ]; then
  curl -OL https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-24/wasi-sdk-24.0-x86_64-linux.tar.gz
  tar -xzf wasi-sdk-24.0-x86_64-linux.tar.gz
  rm wasi-sdk-24.0-x86_64-linux.tar.gz
  mv wasi-sdk-24.0-x86_64-linux wasi-sdk
fi
export WASI_SDK_PATH="$HOME/build/wasi-sdk"
export WASI_SYSROOT="$WASI_SDK_PATH/share/wasi-sysroot"

if [ ! -d rust ]; then
  git clone --filter=blob:none --single-branch --branch compile_rustc_for_wasm17 https://github.com/bjorn3/rust.git rust
fi
cd rust
git checkout compile_rustc_for_wasm17
git rev-parse HEAD
git submodule update --init --depth 1 src/llvm-project

# The patch under test (MinGW LLD driver + link libraries).
RECIPE="${RECIPE:?path to this recipe repo}"
git apply --check "$RECIPE/patches/mingw-lld.patch" && git apply "$RECIPE/patches/mingw-lld.patch"
git diff --stat

cargo install --git https://github.com/oligamiq/toolchain-for-building-rustc
export PATH="$HOME/.cargo/bin:$PATH"
toolchain-for-building-rustc --tier all --os linux --os windows --os mac -f config.llvm.toml --only-llvm

tr '\\' '/' < config.llvm.toml > config.llvm.toml.tmp && mv config.llvm.toml.tmp config.llvm.toml
sed "s|wasi-root = .*|wasi-root = \"${WASI_SYSROOT}\"|g" config.llvm.toml > config.llvm.toml.tmp && mv config.llvm.toml.tmp config.llvm.toml
sed "s|wasi-sdk-24\.0-[^/\"]*|${WASI_SDK_PATH}|g" config.llvm.toml > config.llvm.toml.tmp && mv config.llvm.toml.tmp config.llvm.toml
cat config.llvm.toml

export CC=gcc
export CXX=g++
export RUST_CONFIGURE_ARGS="-W warnings"
export RUSTFLAGS="-W warnings"
ulimit -s 1048576
./x.py install -j"$JOBS" --config config.llvm.toml

echo "=== BUILD COMPLETE ==="
ls -la dist/bin/
echo "DONE"
