#!/bin/bash
set -ex
source "$HOME/.cargo/env"
export WASI_SDK_PATH="$HOME/build/wasi-sdk"
export CC=gcc CXX=g++
ulimit -s 1048576
cd ~/build/rust
grep -q 'x86_64-pc-windows-gnu' config.llvm.toml || {
  sed -i 's|^target = \["x86_64-unknown-linux-gnu", "wasm32-wasip1"\]|target = ["x86_64-unknown-linux-gnu", "wasm32-wasip1", "x86_64-pc-windows-gnu"]|' config.llvm.toml
  printf '\n[target.x86_64-pc-windows-gnu]\ncc = "x86_64-w64-mingw32-gcc"\ncxx = "x86_64-w64-mingw32-g++"\nar = "x86_64-w64-mingw32-ar"\n' >> config.llvm.toml
}
grep -n 'windows' config.llvm.toml
./x.py build --stage 1 library --target x86_64-pc-windows-gnu -j6 --config config.llvm.toml
find build -path '*x86_64-pc-windows-gnu*' -name 'libstd-*.rlib' | head
