# Shared settings, sourced by the other scripts. Override any of these from
# the environment; nothing here is specific to one machine.
#
#   WORK      where everything is cloned/built/downloaded (default: ~/wasm-rustc-build)
#   REPO      git URL of the compiler fork            (default: rad-rs/rust-wasi)
#   BRANCH    branch to build                         (default: wasm-host)
#   WASI_SDK_VERSION  wasi-sdk major version          (default: 24)
#   WASMTIME_VERSION  wasmtime used to run the compiler (default: v28.0.0; newer
#                     releases dropped the WASI threads support the compiler needs)
#   COMPILER_WASM  compiler to run in the test scripts (default: the raw rustc-main.wasm;
#             set it to the output of scripts/optimize.sh to test that)
#   JOBS      parallel build jobs (default: 6; the build was tuned for ~15 GB RAM)
#   LLVM_MINGW_VERSION  llvm-mingw release used for the *-gnullvm targets (default: 20261104)
#   LLVM_MINGW          where that release is unpacked (default: $WORK/llvm-mingw;
#                       scripts/get-llvm-mingw.sh downloads it)
#   TARGET    Windows target the test scripts use: x86_64-pc-windows-gnullvm (default),
#             i686-pc-windows-gnullvm or aarch64-pc-windows-gnullvm

WORK="${WORK:-$HOME/wasm-rustc-build}"
REPO="${REPO:-https://github.com/rad-rs/rust-wasi.git}"
BRANCH="${BRANCH:-wasm-host}"
WASI_SDK_VERSION="${WASI_SDK_VERSION:-24}"
WASMTIME_VERSION="${WASMTIME_VERSION:-v28.0.0}"
LLVM_MINGW_VERSION="${LLVM_MINGW_VERSION:-20261104}"
JOBS="${JOBS:-6}"

RUST_SRC="${RUST_SRC:-$WORK/rust-wasi}"   # override for an existing checkout, e.g. one still named rust-wasm
WASI_SDK="$WORK/wasi-sdk"
WASMTIME="${WASMTIME:-$WORK/wasmtime/wasmtime}"
LLVM_MINGW="${LLVM_MINGW:-$WORK/llvm-mingw}"

# Build outputs.
RUSTC_WASM="${COMPILER_WASM:-$RUST_SRC/build/x86_64-unknown-linux-gnu/stage2-rustc/wasm32-wasip1-threads/release/rustc-main.wasm}"

die() { echo "error: $*" >&2; exit 1; }

need() {
  for f in "$@"; do [ -e "$f" ] || die "missing $f (run scripts/build.sh first?)"; done
}

# select_target TRIPLE: sets TARGET, SYSROOT, WINLIB, MINGW_LIB and RS_OBJECTS
# (1 if the target's sysroot carries rsbegin.o/rsend.o; 0 for every supported target).
#
# The three *-windows-gnullvm targets use llvm-mingw's <arch>-w64-mingw32/lib
# (UCRT, LLVM libunwind, no libgcc), and there are no rsbegin.o/rsend.o: their
# self-contained objects are crt2.o only.
#
# The standard library is looked up in the install tree (dist) first, then in
# the stage1 sysroot, where `x.py build --stage 1 library --target TRIPLE`
# leaves it (a target added after the last full install is only there).
select_target() {
  TARGET="$1"
  RS_OBJECTS=0
  case "$TARGET" in
    x86_64-pc-windows-gnullvm|i686-pc-windows-gnullvm|aarch64-pc-windows-gnullvm)
      MINGW_LIB="$LLVM_MINGW/${TARGET%%-*}-w64-mingw32/lib"
      ;;
    *) die "unsupported TARGET '$TARGET' (x86_64/i686/aarch64-pc-windows-gnullvm)" ;;
  esac
  SYSROOT=""
  for s in "$RUST_SRC/dist" "$RUST_SRC/build/x86_64-unknown-linux-gnu/stage1"; do
    if [ -d "$s/lib/rustlib/$TARGET/lib" ]; then SYSROOT="$s"; break; fi
  done
  # Not an error here: build.sh sources this file before anything is built.
  # Scripts that need the library call need_std.
  WINLIB=""
  [ -z "$SYSROOT" ] || WINLIB="$SYSROOT/lib/rustlib/$TARGET/lib"
}

need_std() {
  [ -n "$WINLIB" ] || die "no $TARGET standard library under $RUST_SRC (run scripts/build.sh first?)"
}

# pe_machine FILE: print the PE header's Machine field (e.g. 0xaa64).
pe_machine() {
  python3 - "$1" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]
print('0x%04x' % struct.unpack_from('<H', d, pe + 4)[0])
PY
}

# expected_machine: the Machine value a $TARGET executable must have.
expected_machine() {
  case "$TARGET" in
    x86_64*)  echo 0x8664 ;;
    i686*)    echo 0x014c ;;
    aarch64*) echo 0xaa64 ;;
  esac
}

# check_pe FILE KIND: KIND is "console" or "GUI". Fails unless the file is a PE
# of that kind for $TARGET (checked with file(1) and the Machine field).
check_pe() {
  local f="$1" kind="$2" want
  case "$TARGET" in
    i686*)    want="PE32 executable.*($kind)" ;;
    aarch64*) want="PE32+ executable.*($kind), ARM64" ;;
    *)        want="PE32+ executable.*($kind)" ;;
  esac
  file "$f" | tee "$(dirname "$f")/file.txt"
  grep -q "$want" "$(dirname "$f")/file.txt" || die "$f is not the expected $TARGET $kind executable"
  [ "$(pe_machine "$f")" = "$(expected_machine)" ] || die "$f has PE machine $(pe_machine "$f"), expected $(expected_machine)"
  echo "OK: $f (PE machine $(pe_machine "$f"))"
}

select_target "${TARGET:-x86_64-pc-windows-gnullvm}"
