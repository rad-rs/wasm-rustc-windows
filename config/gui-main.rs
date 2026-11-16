// Entry point mounted next to the rad sources by scripts/test-gui.sh. Same
// shape as the one the rad designer generates for a native build.
mod rad_core;
mod rad_backend_win32;
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
    let backend = rad_backend_win32::Win32Backend;
    let window = Window::new(&backend, "All controls demo", 460, 410);
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
