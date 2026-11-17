# wasm-rustc-windows

Recipe for building a **WebAssembly-hosted `rustc` that compiles and links Windows executables** (x64 `x86_64-pc-windows-gnullvm`, x86 `i686-pc-windows-gnullvm` and ARM64 `aarch64-pc-windows-gnullvm`) using LLD inside the compiler process, and for running it under wasmtime or in a browser.

It builds [`rad-rs/rust-wasm`](https://github.com/rad-rs/rust-wasm), branch `wasm-host`: 12 commits on top of current `rust-lang/rust` `main` (base `5fb8a16f`, rustc 1.102.0-dev, 2026-11-16). Its LLVM submodule points at [`rad-rs/rustc-llvm-wasi`](https://github.com/rad-rs/rustc-llvm-wasi), branch `wasi-host/23.1`, commit `ce55eea86bafdccd20c3b55fcec0ddf963019a67`. That LLVM branch has exactly two commits on rustc's LLVM base `0a5579eb649d`: (a) YoWASP's WASI-host patch, authored by Catherine and kept under her authorship (applied from [commit `a8982d303c`](https://codeberg.org/YoWASP/llvm-project/commit/a8982d303c) on their `llvmorg-22.1.6+wasm` branch), and (b) "Adapt the WASI-host patch to LLVM 23.1". The result is used by the [RAD designer](https://github.com/rad-rs/rad), which builds Windows `.exe` files in the browser.

Upstream discussion: https://github.com/bjorn3/wasm-rustc/issues/1

## Status

Verified on one machine (Debian 13 on WSL2, 15 GB RAM visible to Linux, wasi-sdk 24, wasmtime v28), with the
configuration in `config/bootstrap.toml.in`:

- The branch builds with `./x.py install` and produces a 132 MB `rustc-main.wasm` (see **Size** below; the earlier
  build with all ten LLVM backends and no stripping was 220 MB) and a `dist/` sysroot with the three
  `*-windows-gnullvm` standard libraries.
- Run under wasmtime v28 with default compiler flags, that compiler compiles and links, for each of
  `x86_64-pc-windows-gnullvm`, `i686-pc-windows-gnullvm` and `aarch64-pc-windows-gnullvm`: a console hello-world and
  the [rad](https://github.com/rad-rs/rad) all-controls demo (8 widget types, GUI subsystem). Each was compiled twice
  in a row per target with no errors (including none from the `SafelyCloseFileDescriptor` path the LLVM patch touches).
  The binaryen 133 `-Os` build of the compiler was used for this retest.
- **x64 and x86 outputs were run on Windows:** the hello-worlds print their message and exit 0; the all-controls demos
  open a window titled `All controls demo` and close cleanly (exit 0). Sizes: x64 1,056,768 B, x86 1,171,968 B.
- **ARM64 output was never run.** The machine used is x86-64 and no emulator was available. The hello-world and the demo
  (894,464 B) were checked only as files: `file` (PE32+ ... ARM64), PE machine `0xaa64`, and `llvm-objdump` from llvm-mingw
  (`coff-arm64`, GUI subsystem, imports from `KERNEL32`, `USER32`, `GDI32`, `COMCTL32` and the UCRT `api-ms-win-crt-*` DLLs).
  Whether they work on ARM64 Windows is unknown.
- **The RAD designer builds in the browser** with this compiler: all four Target options (web app, x64, x86, ARM64), in
  headless Chrome. The first Windows build in a fresh browser profile (which downloads the 104 MB compiler) took about
  9.6-10 s; later builds 4-6 s. With the old 220 MB compiler under the same conditions they took 10.1-10.4 s and
  6.3-6.7 s, so the new compiler is not slower in the browser. The downloaded x64 and x86 executables stay running.
- `x.py test tidy` and `x.py fmt --check` passed on the branch (checked before the slimming; the branch sources did not change).
- **Windows version.** All three targets need Windows 10 or later (UCRT). Earlier versions of this recipe also built
  `x86_64-pc-windows-gnu` and `i686-pc-windows-gnu` (classic `msvcrt.dll`, GCC-style MinGW runtime from Debian's
  `gcc-mingw-w64`); those were dropped. rustc's own platform-support docs list them as Windows 10+ as well; Windows 7
  support exists only in separate tier-3 `*-win7-windows-gnu` targets, which this recipe does not build.
- One intermittent failure was seen: the very first compile after a reboot crashed inside the `wasmtime` process itself
  (kernel log: segfault in `wasmtime`); the 40+ compiles after that, with the same files, had no failure.
- `wasm-opt` crashes on this module with `-Oz` (and, with the Debian binaryen 120, with `-O2`); see **Size**.

**Not verified**

- `scripts/build.sh` has **not** been run from scratch. The compiler was built by hand over many attempts; the script
  automates those steps and its generated config was diffed against the one that built (they differ only in the live
  file's `submodules = false` and section order). `scripts/get-wasmtime.sh` has not been run either.
- Native test suites (ui, run-make) were not run, and no native `x.py check` was run on its own. Only compile-and-link of two
  small programs per target was tested; other crates, other targets (`-msvc`, `-gnu`) and other hosts were not.
- The designer tests used its default empty form; the all-controls demo went through the wasmtime scripts, not the designer.
- The cranelift backend is not ported; this is LLVM only.

## Requirements

Debian/Ubuntu packages (names as on Debian 13):

```
sudo apt-get install build-essential cmake ninja-build pkg-config python3 git curl \
  ca-certificates libssl-dev libclang-dev xz-utils unzip
```

No GCC MinGW packages are needed: all three targets use llvm-mingw.

The three `*-windows-gnullvm` targets (x86_64, i686, ARM64) need [llvm-mingw](https://github.com/mstorsjo/llvm-mingw) (UCRT flavour, MIT-licensed; its LLVM and mingw-w64 parts have their own licences, see `LICENSE.TXT` in the archive) for its MinGW runtime (`crt2.o`, import libraries, `libunwind`) and the clang wrappers bootstrap uses to build the standard library's C parts. `scripts/get-llvm-mingw.sh` downloads release 20261104 (about 80 MB, 620 MB unpacked) into `$WORK/llvm-mingw`; `scripts/build.sh` runs it for you. Nothing from llvm-mingw is redistributed by this repository.

`x86_64-w64-mingw32-g++` is not installed by this and is not needed (bootstrap prints a harmless "compiler family detection failed" warning). Plan for about **18 GB** of disk for the build directory (the `dist/` sysroot is about 0.5 GB) and about 15 GB of RAM.

## Build

```
scripts/build.sh                 # clone, configure, build + install (hours; see below)
scripts/get-wasmtime.sh          # wasmtime v28, needed to run the compiler
```

Everything lands under `$WORK` (default `~/wasm-rustc-build`); see `scripts/env.sh` for the settings (`WORK`, `REPO`, `BRANCH`, `JOBS`, ...). What `build.sh` does:

1. installs Rust via rustup if there is no `cargo`, downloads wasi-sdk 24;
2. clones `rad-rs/rust-wasm` branch `wasm-host` (blobless, single branch) and fetches the LLVM submodule with `--depth 1`;
3. writes `bootstrap.toml` from `config/bootstrap.toml.in` (host `wasm32-wasip1-threads`; targets `x86_64-unknown-linux-gnu`, `wasm32-wasip1` and the three `*-windows-gnullvm` triples; LLVM backends `AArch64;X86` only; `llvm-tools = false`);
4. exports `WASI_SDK_PATH` and `WASI_SYSROOT`, sets a 1 GB stack limit and runs `./x.py install -j6 --config bootstrap.toml`.

Timings measured on the build machine at `-j6`: the host LLVM took about 19 minutes, the wasm LLVM about 17, and the compiler and standard-library builds that followed about 15-25 minutes more (a first build from nothing builds the host LLVM too and takes a couple of hours in total).

Output: `rust-wasm/build/x86_64-unknown-linux-gnu/stage2-rustc/wasm32-wasip1-threads/release/rustc-main.wasm` (the compiler) and `rust-wasm/dist/` (the sysroot).

## Run

```
wasmtime run -Sthreads=y -Spreview2=n \
  --dir WORK::/work --dir DIST::/sysroot --dir MINGW::/mingw \
  --env RUST_MIN_STACK=16777216 --env RUSTC_BOOTSTRAP=1 \
  rustc-main.wasm /work/hello.rs --crate-name hello --edition 2021 \
  --target x86_64-pc-windows-gnullvm --sysroot /sysroot \
  --color never --error-format short \
  -C linker-flavor=ld.lld -C link-arg=/mingw/crt2.o -C link-arg=-L/mingw \
  -o /work/hello.exe
```

`scripts/test-hello.sh` does exactly this and checks the result is a PE32+ executable (it checks the PE header's Machine field too). `TARGET` selects the target: `x86_64-pc-windows-gnullvm` (default), `i686-pc-windows-gnullvm` or `aarch64-pc-windows-gnullvm` (all need `scripts/get-llvm-mingw.sh` first; the checker expects PE32 for i686 and PE32+ otherwise). For ARM64 it only checks that the result links and that the header says ARM64 (it cannot run it); `env.sh` picks the matching MinGW directory and the sysroot that holds that target's standard library. `RAD_CRATES=<rad>/crates scripts/test-gui.sh` builds the rad all-controls demo into a GUI exe (add `-C link-arg=--subsystem=windows`, as the script does, so it has no console window).

The Windows sysroot is `dist/lib/rustlib/<triple>/lib/` (the `.rlib`/`.rmeta` pairs). The `gnullvm` targets have no `rsbegin.o`/`rsend.o`: the only self-contained object is `crt2.o` (from llvm-mingw's `<arch>-w64-mingw32/lib`), and the target links `-lmingw32 -lmingwex -lmsvcrt -lkernel32 -luser32` plus `libunwind.a` (from the target spec; `-m arm64pe` comes from it too for ARM64).

### For the RAD designer

```
scripts/assemble-designer-toolchain.sh DEST    # e.g. <rad>/crates/rad-designer/native-toolchain
```

produces the directory the designer's native pipeline downloads (all three Windows targets by default; pass the triples you want after `DEST` to build fewer):

```
rustc_opt.wasm                    the compiler (rustc-main.wasm under the name the pipeline expects), shared
<triple>/crt2.o                   MinGW C runtime start-up object
<triple>/mingw-libs/*.a           import libraries + libunwind, with index.json (JSON array of stems)
<triple>/sysroot/*.rlib *.rmeta   the target's standard library, rustc's hash suffix removed
<triple>/sysroot/index.json       JSON array of rlib stems
```

Each `.rlib` needs its `.rmeta` beside it (the rlib alone is a metadata stub). The designer's 32-bit (x86) build also needs a `rad-backend-win32` that binds `SetWindowLongPtrW`/`GetWindowLongPtrW` to `SetWindowLongW`/`GetWindowLongW` on 32-bit, because 32-bit `user32` has no `*LongPtr*` exports; that fix is in the rad repo.

## Size

The compiler wasm is the thing to keep small for the browser (and for hosting). Measured on this build:

| compiler wasm | raw bytes | gzip -9 | brotli -q 11 | `wasm-opt` time / peak RAM |
|---|---|---|---|---|
| earlier build: all 10 LLVM backends, no strip | 220,511,776 | 45,232,500 | 27,431,806 | - |
| **this recipe, raw** (`AArch64;X86;WebAssembly`, `strip = true`) | 132,381,060 | 34,104,235 | 20,609,256 | - |
| `-Os`, binaryen 133 (what the designer was tested with) | 108,517,125 | 34,088,737 | 21,278,872 | 2 min 5 s / 4.8 GB |
| `-Os`, binaryen 120 (Debian) | 108,686,496 | 34,162,622 | 21,309,882 | 3 min 21 s / 5.5 GB |
| `-O2`, binaryen 133 | 112,905,859 | 34,423,302 | 21,449,341 | 1 min 15 s / 4.7 GB |
| `-Oz`, binaryen 120 or 133 | crashes | | | |

- Dropping the seven unneeded LLVM backends and stripping debug info took 40% off the raw size.
- **`wasm-opt` does not shrink the download.** It cuts the raw size by 15-18%, but brotli of the raw file is already
  20.6 MB and brotli of the `-Os` output is 21.3 MB (gzip is the same). It still helps the uncompressed size and
  the wasmtime run time (hello-world compile, 10-run average: raw 2003 ms, `-Os` 1745 ms, `-O2` 1786 ms). If you
  only care about transfer size, shipping the raw file is as good and avoids the optimiser; the designer was
  tested with the `-Os` build.
- **`-Oz` crashes `wasm-opt`**: SIGSEGV after 53 s with binaryen 120 (with an unlimited stack: "stack smashing
  detected"), SIGSEGV after 16 s with binaryen 133, SIGILL or an internal assertion with extra `--enable-*` flags. `-O2`
  also crashes binaryen 120 (SIGSEGV after 21 s) but works with 133. `-Os` worked with both. `wasm-opt` also needs the
  1 GB stack that the script sets (with the default 8 MB it segfaulted on the earlier baseline).
- `rust.strip = true` strips the module's `target_features` section, so `wasm-opt --print-features` no longer works and
  `scripts/optimize.sh` falls back to an explicit feature list (threads, mutable-globals, nontrapping-float-to-int,
  bulk-memory, sign-ext, reference-types, multivalue).
- The first wasmtime run of a new wasm file takes 16-19 s (it compiles the module and caches it); later runs take about 2 s.

```
scripts/optimize.sh [IN [OUT]]              # default -Os; OPT=-O2, SIZES=1 (print gzip/brotli sizes), WASM_OPT=/path/to/wasm-opt
COMPILER_WASM=$WORK/rustc_opt.wasm scripts/test-hello.sh    # test the optimised compiler before shipping it
```

Binaryen 133 (a release tarball from github.com/WebAssembly/binaryen) was used for the `-Os` variant above; the script
uses `wasm-opt` from `PATH` unless `WASM_OPT` is set.

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
- `.gitmodules`: point the LLVM submodule at `rad-rs/rustc-llvm-wasi`, branch `wasi-host/23.1` (the last commit of the 12)

**One change is not gated**: `rustc_driver` is now built as `["lib", "dylib"]` for every host (cargo cannot gate a crate type), so native builds produce one extra rlib. The LLVM patch (22 files) lives on the `wasi-host/23.1` branch of [`rad-rs/rustc-llvm-wasi`](https://github.com/rad-rs/rustc-llvm-wasi), which the submodule points at: two commits on rustc's LLVM base `0a5579eb649d`, YoWASP's patch by Catherine (authorship kept) and our "Adapt the WASI-host patch to LLVM 23.1" (the `AddSignalHandler` signature, the `posix_madvise` guard for `randomAccessImpl`, and so on).

## Gotchas

- **Build all the Windows targets' standard libraries in one command.** `x.py build --stage 1 library --target A` leaves only `A` in the stage1 sysroot and drops an earlier target built that way. Use one comma-separated list, e.g. `--target x86_64-pc-windows-gnullvm,i686-pc-windows-gnullvm,aarch64-pc-windows-gnullvm` (repeating `--target` is rejected), or let `x.py install` put them all in `dist/`.
- **`-gnullvm` import libraries are found empirically.** The 15 import libraries in each toolchain directory (the same set for x86_64, i686 and ARM64) are what linking the all-controls demo needed (`lld` reported each missing `-l` in turn); a program using other Windows APIs may need more. `libucrt.a` and `libmsvcrt.a` are the same file in llvm-mingw's UCRT flavour, so only `libmsvcrt` is shipped.
- **`llvm.targets` must keep `WebAssembly`**, and changing it needs a clean slate. The native stage1 rustc cross-builds the wasm host's std and rustc; without the WebAssembly backend that fails with `Unknown command line argument '-wasm-enable-eh'`. Bootstrap's "LLVM finished" stamp does not track the target list, so after changing it delete `build/x86_64-unknown-linux-gnu/llvm`, `build/wasm32-wasip1-threads/llvm` and the `stage1`, `stage1-rustc`, `stage1-std`, `stage1-tools-bin` and `stage2-rustc` build directories before rebuilding; otherwise bootstrap keeps using the old LLVM and the stage1 compiler built against it.
- **Stale CMake cache.** After a *failed* wasm LLVM build, delete `rust-wasm/build/wasm32-wasip1-threads/llvm` before re-running. Otherwise CMake notices changed variables, re-runs without the `-D` overrides and the next build fails in unrelated ways.
- **`WASI_SYSROOT` must be exported** when running `x.py`; without it the link picked the non-threads libc (errors about `mman.o` and `errno` TLS).
- **`llvm-tools = false`** is required in `bootstrap.toml`; otherwise stage2 assembly panics copying LLVM tools.
- **wasmtime v28.** wasmtime 50 reports "`-Sthreads` flag is no longer supported". Newer releases between those were not tried.
- **Preopen layout.** The compiler needs the work dir, sysroot and MinGW dir mounted; `--color never --error-format short` make failures readable (without them diagnostics were lost on the abort path).
- **Intermittent clang segfault.** One early build on a predecessor of this branch segfaulted in `libgcc_s` with 8 jobs and an unlimited stack. It never reproduced on its own; the 1 GB stack limit and `-j6` were used afterwards and it did not recur.
- **Browser use needs the `.rmeta` files** next to each `.rlib` (current rustc treats the rlib as a metadata stub), and the designer's pipeline reads the two `index.json` manifests.

## Acknowledgements and credits

- [bjorn3](https://github.com/bjorn3): the original work on compiling rustc to WebAssembly ([`bjorn3/rust`](https://github.com/bjorn3/rust), `compile_rustc_for_wasm*` branches; see also [`bjorn3/wasm-rustc`](https://github.com/bjorn3/wasm-rustc)). The branch here is a port of those changes to current rustc; eight of its commits carry a `Co-authored-by` trailer for that reason.
- [YoWASP](https://codeberg.org/YoWASP/llvm-project) (their GitHub organisation is archived; the project moved to Codeberg): **Catherine** wrote the WASI-host patch for LLVM (`main+wasm` and the per-release `llvmorg-*+wasm` branches). The LLVM branch here keeps her commit under her authorship and adapts it from LLVM 22.1 to rustc's LLVM 23.1 in a separate commit.
- [oligamiq/rubrc](https://github.com/oligamiq/rubrc): a wasm-hosted rustc/cargo in the browser, and the browser WASI shims this work builds on.
- The Rust project: `rust-lang/rust` and `rust-lang/llvm-project` (rustc's LLVM fork, the base of the LLVM branch).
- [llvm-mingw](https://github.com/mstorsjo/llvm-mingw): the MinGW runtime and clang wrappers for the `-gnullvm` targets.

## Licence

No licence has been chosen for the scripts in this repository yet. The compiler and LLVM changes are modifications of code under their upstream licences (Rust: MIT OR Apache-2.0; LLVM: Apache-2.0 with LLVM exceptions).
