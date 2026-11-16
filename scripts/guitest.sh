cd ~/build
CR="${RAD_CRATES:?path to the rad repo crates/ directory}"
R=~/build/rust
WASM=$R/build/x86_64-unknown-linux-gnu/stage1-rustc/wasm32-wasip1-threads/release/rustc-main.wasm
# reuse wt/{root,sysroot,mingw} from the hello test; fresh app dir
rm -rf wt/app && mkdir -p wt/app/rad_core
cp $CR/rad-core/src/lib.rs wt/app/rad_core.rs
for f in button checkbox label picture_box progress_bar radio_button textbox tree_view widget window; do
  sed 's/crate::/crate::rad_core::/g' $CR/rad-core/src/$f.rs > wt/app/rad_core/$f.rs
done
sed 's/rad_core::/crate::rad_core::/g' $CR/rad-backend-win32-min/src/lib.rs > wt/app/rad_backend_win32_min.rs
sed 's/rad_core::/crate::rad_core::/g' $CR/rad-demo/src/form1.rs > wt/app/form1.rs
sed 's/rad_core::/crate::rad_core::/g' $CR/rad-demo/src/form1.designer.rs > wt/app/form1.designer.rs
cat > wt/app/main.rs <<'RS'
mod rad_core;
mod rad_backend_win32_min;
#[path = "form1.rs"]
mod form1;

use rad_core::Window;

#[link(name = "user32")]
unsafe extern "system" {
    fn GetMessageW(lpmsg: *mut [usize; 7], hwnd: *mut core::ffi::c_void, wmsgfiltermin: u32, wmsgfiltermax: u32) -> i32;
    fn TranslateMessage(lpmsg: *const [usize; 7]) -> i32;
    fn DispatchMessageW(lpmsg: *const [usize; 7]) -> isize;
}

fn main() {
    let backend = rad_backend_win32_min::Win32Backend;
    let window = Window::new(&backend, "Form1", 640, 480);
    let form = form1::build(&window);

    unsafe {
        let mut msg: [usize; 7] = [0; 7];
        while GetMessageW(&mut msg, core::ptr::null_mut(), 0, 0) != 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    std::mem::forget(form);
    std::mem::forget(window);
}
RS
cp wt/root/rsbegin.o wt/app/ 2>/dev/null; cp wt/root/rsend.o wt/app/ 2>/dev/null
rm -f wt/app/hello.exe
./wasmtime28/wasmtime run -Sthreads=y -Spreview2=n \
  --dir wt/root::/ --dir wt/app::/work --dir wt/sysroot::/sysroot --dir wt/mingw::/mingw \
  --env RUST_MIN_STACK=16777216 --env RUSTC_BOOTSTRAP=1 --env TMPDIR=/work \
  $WASM /work/main.rs --crate-name app --crate-type bin --edition 2021 \
  --target x86_64-pc-windows-gnu --sysroot /sysroot \
  --color never --error-format short \
  -C linker-flavor=ld.lld -C link-arg=/mingw/crt2.o -C link-arg=-L/mingw \
  -C link-arg=--subsystem=windows -o /work/out.exe 2>&1 | grep -v '^ *[0-9]*: 0x' | grep -v '^Linking using\|^LC_ALL' | head -40 | cut -c1-400
echo "rc=${PIPESTATUS[0]}"
file wt/app/out.exe; ls -la wt/app/out.exe 2>&1
