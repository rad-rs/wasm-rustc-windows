cd ~/build
R=~/build/rust
WASM=$R/build/x86_64-unknown-linux-gnu/stage1-rustc/wasm32-wasip1-threads/release/rustc-main.wasm
SYS=$R/build/x86_64-unknown-linux-gnu/stage1
MINGW=/usr/x86_64-w64-mingw32/lib
GCC=$(dirname $(find /usr/lib/gcc/x86_64-w64-mingw32 -name libgcc_eh.a | head -1))
rm -rf wt && mkdir -p wt/work wt/mingw && cp $MINGW/*.a $MINGW/crt2.o $GCC/*.a wt/mingw/
echo 'fn main() { println!("Hello from wasm-hosted rustc!"); }' > wt/work/hello.rs
S="$SYS/lib/rustlib/x86_64-pc-windows-gnu/lib"
ls $S | head -3
./wasmtime28/wasmtime run -Sthreads=y -Spreview2=n -Sthreads=y \
  --dir wt/work::/work --dir $SYS::/sysroot --dir wt/mingw::/mingw \
  --env RUST_MIN_STACK=16777216 --env RUSTC_BOOTSTRAP=1 \
  $WASM -- /work/hello.rs --crate-name hello --edition 2021 \
  --target x86_64-pc-windows-gnu --sysroot /sysroot \
  -C linker-flavor=ld.lld -C link-arg=/mingw/crt2.o -C link-arg=-L/mingw \
  -o /work/hello.exe 2>&1 | tail -30
echo "rustc rc=${PIPESTATUS[0]}"
ls -la wt/work; file wt/work/hello.exe
