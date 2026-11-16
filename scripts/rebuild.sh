source "$HOME/.cargo/env"
export WASI_SDK_PATH="$HOME/build/wasi-sdk"
export WASI_SYSROOT="$WASI_SDK_PATH/share/wasi-sysroot"
export CC=gcc CXX=g++ RUST_CONFIGURE_ARGS="-W warnings" RUSTFLAGS="-W warnings"
export PATH="$HOME/.cargo/bin:$PATH"
ulimit -s 1048576
cd ~/build/rust
./x.py install -j6 --config config.llvm.toml
