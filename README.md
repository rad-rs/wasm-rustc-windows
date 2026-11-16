# wasm-rustc-windows

Recipe for building a **WebAssembly-hosted `rustc` that compiles and links Windows executables** (`x86_64-pc-windows-gnu` and `i686-pc-windows-gnu`) using LLD inside the compiler process, and for running it under wasmtime or in a browser.

It builds [`rad-rs/rust-wasm`](https://github.com/rad-rs/rust-wasm), branch `wasm-host`: 11 commits on top of current `rust-lang/rust` `main` (base `5fb8a16f`, rustc 1.102.0-dev, 2026-11-16). Its LLVM submodule is [`rad-rs/llvm-project`](https://github.com/rad-rs/llvm-project), branch `wasi-host-support`. The result is used by the [RAD designer](https://github.com/rad-rs/rad), which builds Windows `.exe` files in the browser.

Upstream discussion: https://github.com/bjorn3/wasm-rustc/issues/1

## Status

Verified (on one machine: Debian 13 on WSL2, 15 GB RAM visible to Linux, wasi-sdk 24):

- The branch builds with `./x.py install`, giving a 220 MB `rustc-main.wasm` and a `dist/` sysroot that includes the `x86_64-pc-windows-gnu` standard library. `i686-pc-windows-gnu` is built the same way (`bootstrap.toml.in` lists it); on the machine used here it was added later and built with `x.py build --stage 1 library --target i686-pc-windows-gnu`, so its standard library is in `build/x86_64-unknown-linux-gnu/stage1/` and not in `dist/` (the scripts look in both). That change reconfigured the wasm LLVM, and the standard-library build took about 5 minutes.
- Run under wasmtime v28 with **default compiler flags**, it compiles and links:
  - a console hello-world: a PE32+ console exe that prints its message and exits 0 on Windows;
  - the [rad](https://github.com/rad-rs/rad) all-controls demo (all 8 widget types): a PE32+ GUI exe that opens a window titled `All controls demo` and closes cleanly (exit 0);
  - the same hello-world and all-controls demo for **`i686-pc-windows-gnu`** (`TARGET=i686-pc-windows-gnu`): PE32 (Intel i386) exes that run on 64-bit Windows under WoW64. The hello-world prints its message and exits 0; the GUI demo opens `All controls demo` and closes cleanly. Linking worked with the same compiler and flags, with no compiler change.
- The RAD designer builds an `.exe` in the browser with this compiler (about 9-10 s, against about 6 s with the older toolchain it replaced).
- `x.py test tidy` and `x.py fmt --check` passed on the branch. The binary under test was built just before a formatting-only fixup (identical content otherwise).
- Every script here was checked with `bash -n`; `build.sh config`, `assemble-designer-toolchain.sh`, `test-hello.sh` and `test-gui.sh` were run against the existing build (see below). The LLVM submodule commit is fetchable by SHA.

**Not verified**

- `scripts/build.sh` has **not** been run end to end. The compiler was built by hand over 12 attempts; the script automates those steps and its generated config was checked against the one that built successfully, but a from-scratch run of the script itself hasn't happened. `scripts/get-wasmtime.sh` has not been run either.
- Native test suites (ui, run-make) were not run, and no native `x.py check` was run on its own. Only compile-and-link of two small programs was tested; other crates, other targets (`-msvc`, aarch64) and other hosts were not.
- The cranelift backend is not ported; this is LLVM only.

## Requirements

Debian/Ubuntu packages (names as on Debian 13):

```
sudo apt-get install build-essential cmake ninja-build pkg-config python3 git curl \
  ca-certificates libssl-dev libclang-dev xz-utils unzip gcc-mingw-w64-x86-64 gcc-mingw-w64-i686
```

(`gcc-mingw-w64-i686` is only needed for the 32-bit target.)

`x86_64-w64-mingw32-g++` is not installed by this and is not needed (bootstrap prints a harmless "compiler family detection failed" warning). Plan for about **18 GB** of disk for the build directory (the `dist/` sysroot is about 0.5 GB) and about 15 GB of RAM.

## Build

```
scripts/build.sh                 # clone, configure, build + install (hours; see below)
scripts/get-wasmtime.sh          # wasmtime v28, needed to run the compiler
```

Everything lands under `$WORK` (default `~/wasm-rustc-build`); see `scripts/env.sh` for the settings (`WORK`, `REPO`, `BRANCH`, `JOBS`, ...). What `build.sh` does:

1. installs Rust via rustup if there is no `cargo`, downloads wasi-sdk 24;
2. clones `rad-rs/rust-wasm` branch `wasm-host` (blobless, single branch) and fetches the LLVM submodule with `--depth 1`;
3. writes `bootstrap.toml` from `config/bootstrap.toml.in` (host `wasm32-wasip1-threads`; targets `x86_64-unknown-linux-gnu`, `wasm32-wasip1`, `x86_64-pc-windows-gnu`; LLVM backend only; `llvm-tools = false`);
4. exports `WASI_SDK_PATH` and `WASI_SYSROOT`, sets a 1 GB stack limit and runs `./x.py install -j6 --config bootstrap.toml`.

Timings measured on the build machine at `-j6`: the wasm LLVM took about 19 minutes; each later rustc rebuild took 10-14 minutes. A first build from nothing also builds the host LLVM and takes hours.

Output: `rust-wasm/build/x86_64-unknown-linux-gnu/stage2-rustc/wasm32-wasip1-threads/release/rustc-main.wasm` (the compiler) and `rust-wasm/dist/` (the sysroot).

## Run

```
wasmtime run -Sthreads=y -Spreview2=n \
  --dir WORK::/work --dir DIST::/sysroot --dir MINGW::/mingw \
  --env RUST_MIN_STACK=16777216 --env RUSTC_BOOTSTRAP=1 \
  rustc-main.wasm /work/hello.rs --crate-name hello --edition 2021 \
  --target x86_64-pc-windows-gnu --sysroot /sysroot \
  --color never --error-format short \
  -C linker-flavor=ld.lld -C link-arg=/mingw/crt2.o -C link-arg=-L/mingw \
  -o /work/hello.exe
```

`scripts/test-hello.sh` does exactly this and checks the result is a PE32+ executable. For 32-bit, run it with `TARGET=i686-pc-windows-gnu` (the check then expects PE32); `env.sh` picks the matching MinGW directories and the sysroot that holds that target's standard library. `RAD_CRATES=<rad>/crates scripts/test-gui.sh` builds the rad all-controls demo into a GUI exe (add `-C link-arg=--subsystem=windows`, as the script does, so it has no console window).

The Windows sysroot is `dist/lib/rustlib/x86_64-pc-windows-gnu/lib/` (it contains `rsbegin.o`, `rsend.o` and the `.rlib`/`.rmeta` pairs). The MinGW runtime comes from Debian's `gcc-mingw-w64-x86-64`: `crt2.o` and the import libraries from `/usr/x86_64-w64-mingw32/lib`, and `libgcc`/`libgcc_eh` from the **`*-win32`** gcc directory. A `*-posix` directory sits next to it with different `libgcc` files, so the scripts select `-win32` explicitly.

### For the RAD designer

```
scripts/assemble-designer-toolchain.sh DEST    # e.g. <rad>/crates/rad-designer/native-toolchain
```

produces the directory the designer's native pipeline downloads (for both targets by default, or pass the triples you want after `DEST`):

```
rustc_opt.wasm                    the compiler (rustc-main.wasm under the name the pipeline expects), shared
<triple>/crt2.o                   MinGW C runtime start-up object
<triple>/mingw-libs/*.a           import libraries + libgcc, with index.json (JSON array of stems)
<triple>/sysroot/*.rlib *.rmeta   the target's standard library, rustc's hash suffix removed
<triple>/sysroot/rsbegin.o rsend.o
<triple>/sysroot/index.json       JSON array of rlib stems
```

Each `.rlib` needs its `.rmeta` beside it (the rlib alone is a metadata stub). The designer's 32-bit build also needs a `rad-backend-win32` that binds `SetWindowLongPtrW`/`GetWindowLongPtrW` to `SetWindowLongW`/`GetWindowLongW` on 32-bit, because 32-bit `user32` has no `*LongPtr*` exports; that fix is in the rad repo.

## What the branch changes

Commits on `rust-lang/rust` `main` (most are gated to WASI hosts or to `cfg(target_family = "wasm")`, so other hosts are not affected):

- `wasm32-wasip1-threads`: link against emulated mman
- `rustc_llvm`: build and link an in-process LLD driver for WASI hosts (ELF, wasm and **MinGW** drivers, plus the extra lld/LLVM libraries they need)
- `rustc_codegen_ssa`: link through in-process LLD when hosted on WASI
- `rustc_metadata`: don't use `libloading` on platforms without `dlopen`
- `rustc_interface`, `rustc_driver_impl`: run on the current thread on wasm hosts
- `bootstrap`: support building rustc for a WASI host (this also keeps bootstrap's default of 2 frontend threads off for WASI; with it on the compiler panics in `parking_lot_core`)
- `rustc_driver`: also build an rlib so wasm hosts can link it
- `rustc_codegen_llvm`: don't require `libloading::Library` on platforms without `dlopen`
- `rustc_session`: no panic on a missing default sysroot on WASI; skip the output writeability check on WASI
- `.gitmodules`: use `rad-rs/llvm-project`

**One change is not gated**: `rustc_driver` is now built as `["lib", "dylib"]` for every host (cargo cannot gate a crate type), so native builds produce one extra rlib. The LLVM patch (22 files) lives on the `wasi-host-support` branch of the LLVM fork, which the submodule points at.

## Gotchas

- **Stale CMake cache.** After a *failed* wasm LLVM build, delete `rust-wasm/build/wasm32-wasip1-threads/llvm` before re-running. Otherwise CMake notices changed variables, re-runs without the `-D` overrides and the next build fails in unrelated ways.
- **`WASI_SYSROOT` must be exported** when running `x.py`; without it the link picked the non-threads libc (errors about `mman.o` and `errno` TLS).
- **`llvm-tools = false`** is required in `bootstrap.toml`; otherwise stage2 assembly panics copying LLVM tools.
- **wasmtime v28.** wasmtime 50 reports "`-Sthreads` flag is no longer supported". Newer releases between those were not tried.
- **Preopen layout.** The compiler needs the work dir, sysroot and MinGW dir mounted; `--color never --error-format short` make failures readable (without them diagnostics were lost on the abort path).
- **Intermittent clang segfault.** One early build on a predecessor of this branch segfaulted in `libgcc_s` with 8 jobs and an unlimited stack. It never reproduced on its own; the 1 GB stack limit and `-j6` were used afterwards and it did not recur.
- **Browser use needs the `.rmeta` files** next to each `.rlib` (current rustc treats the rlib as a metadata stub), and the designer's pipeline reads the two `index.json` manifests.

## Credits

- [bjorn3](https://github.com/bjorn3): the original work on compiling rustc to WebAssembly ([`bjorn3/rust`](https://github.com/bjorn3/rust), `compile_rustc_for_wasm*` branches; see also [`bjorn3/wasm-rustc`](https://github.com/bjorn3/wasm-rustc)). The branch here is a port of those changes to current rustc; eight of its commits carry a `Co-authored-by` trailer for that reason.
- [YoWASP/llvm-project](https://github.com/YoWASP/llvm-project) (`main+wasm`): the WASI-host patches for LLVM, adapted here from LLVM 22.1 to rustc's LLVM 23.1.
- [oligamiq/rubrc](https://github.com/oligamiq/rubrc): a wasm-hosted rustc/cargo in the browser, and the browser WASI shims this work builds on.
- The Rust project: `rust-lang/rust` and `rust-lang/llvm-project`.

## Licence

No licence has been chosen for the scripts in this repository yet. The compiler and LLVM changes are modifications of code under their upstream licences (Rust: MIT OR Apache-2.0; LLVM: Apache-2.0 with LLVM exceptions).
