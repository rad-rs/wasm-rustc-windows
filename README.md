# wasm-rustc-windows

Notes, patch and scripts for building a **WebAssembly-hosted `rustc` that links Windows executables** (`x86_64-pc-windows-gnu`) using its in-process LLD, and for running it under wasmtime or in a browser.

Built on [bjorn3's `compile_rustc_for_wasm17`](https://github.com/bjorn3/rust/tree/compile_rustc_for_wasm17) branch (wasm-host rustc work; see also [bjorn3/wasm-rustc](https://github.com/bjorn3/wasm-rustc) and [oligamiq/rubrc](https://github.com/oligamiq/rubrc)). Upstream discussion: https://github.com/bjorn3/wasm-rustc/issues/1

## Status

Verified once, on one machine:

- A console hello-world and a small Win32 GUI app, compiled by the wasm `rustc` for `x86_64-pc-windows-gnu`, produced valid PE32+ executables that launched and ran on Windows.
- The same toolchain, driven from the in-browser designer pipeline in [rad-rs/rad](https://github.com/rad-rs/rad), produced a working `.exe`.

Not verified: other targets, other crates, other hosts than Debian 13 (WSL2), anything beyond the tested base commit.

Work to port this onto current `rust-lang/rust` is in progress separately and is not part of this recipe yet.

## What the patch does

`patches/mingw-lld.patch` (applies cleanly to `compile_rustc_for_wasm17` at `3e2c4d30`):

1. `llvm-wrapper/LLD.cpp`: register the MinGW LLD driver (`lld::MinGW` → `lld::mingw::link`).
2. `rustc_llvm/build.rs`: link `lldMinGW`, `lldCOFF`, `LLVMWindowsDriver`, `LLVMLibDriver` and `LLVMWindowsManifest`.

The LLVM build already produces these libraries. The first change alone is not enough: without the link lines the wasm builds but fails to start with `unknown import: env::...lld5mingw4link...`.

## Other things the build needed

See `patches/local-cxx-target-workaround.md` for the C++ target-flag workaround (`scripts/cxxw.sh`). Also:

- Export `WASI_SDK_PATH` (wasi-sdk 24) **and** `WASI_SYSROOT`; without the latter the link picks the non-threads libc.
- Use `-j6` and `ulimit -s 1048576`; one early run segfaulted in clang with 8 jobs and an unlimited stack. Not reproducible, cause unknown.
- `x.py install` ends with a panic about a missing `llvm-objcopy.wasm`. It happens after the compiler is built; the binary is at `build/x86_64-unknown-linux-gnu/stage1-rustc/wasm32-wasip1-threads/release/rustc-main.wasm`.
- Run it with **wasmtime v28**: newer wasmtime removed WASI threads support.
- The wasm `rustc` needs `/` preopened (`--dir <root>::/`; `TMPDIR` is ignored), `rsbegin.o`/`rsend.o` next to the rlibs, and `--color never --error-format short` to see diagnostics.
- Windows sysroot: build the `x86_64-pc-windows-gnu` standard library with the same source (`scripts/winstd.sh`) and take `crt2.o` and the import libraries from Debian's `gcc-mingw-w64-x86-64`.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/build-wasm17.sh` | Clone, patch and build the wasm host compiler (long: hours). Set `RECIPE` to this repo's path. |
| `scripts/rebuild.sh` | Re-run `x.py install` after a source change. |
| `scripts/winstd.sh` | Build the Windows-gnu standard library with that compiler. |
| `scripts/wintest.sh` | Hello-world compile test under wasmtime. |
| `scripts/guitest.sh` | Build a GUI app (the rad demo) the same way; set `RAD_CRATES`. |
| `scripts/cxxw.sh` | Compiler wrapper for the C++ target workaround. |

The scripts were written for one machine and read like it (paths under `~/build`); treat them as documentation of what worked, and expect to adjust them.

## Licence

No licence has been chosen yet. The patch is a small modification of code under the Rust project's licences (MIT OR Apache-2.0).
