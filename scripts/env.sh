# Shared settings, sourced by the other scripts. Override any of these from
# the environment; nothing here is specific to one machine.
#
#   WORK      where everything is cloned/built/downloaded (default: ~/wasm-rustc-build)
#   REPO      git URL of the compiler fork            (default: rad-rs/rust-wasm)
#   BRANCH    branch to build                         (default: wasm-host)
#   WASI_SDK_VERSION  wasi-sdk major version          (default: 24)
#   WASMTIME_VERSION  wasmtime used to run the compiler (default: v28.0.0; newer
#                     releases dropped the WASI threads support the compiler needs)
#   JOBS      parallel build jobs (default: 6; the build was tuned for ~15 GB RAM)
#   LLVM_MINGW_VERSION  llvm-mingw release used for the ARM64 target (default: 20261104)
#   LLVM_MINGW          where that release is unpacked (default: $WORK/llvm-mingw;
#                       scripts/get-llvm-mingw.sh downloads it)
#   TARGET    Windows target the test/assemble scripts use: x86_64-pc-windows-gnu
#             (default), i686-pc-windows-gnu or aarch64-pc-windows-gnullvm

WORK="${WORK:-$HOME/wasm-rustc-build}"
REPO="${REPO:-https://github.com/rad-rs/rust-wasm.git}"
BRANCH="${BRANCH:-wasm-host}"
WASI_SDK_VERSION="${WASI_SDK_VERSION:-24}"
WASMTIME_VERSION="${WASMTIME_VERSION:-v28.0.0}"
LLVM_MINGW_VERSION="${LLVM_MINGW_VERSION:-20261104}"
JOBS="${JOBS:-6}"

RUST_SRC="$WORK/rust-wasm"
WASI_SDK="$WORK/wasi-sdk"
WASMTIME="${WASMTIME:-$WORK/wasmtime/wasmtime}"
LLVM_MINGW="${LLVM_MINGW:-$WORK/llvm-mingw}"

# Build outputs.
RUSTC_WASM="$RUST_SRC/build/x86_64-unknown-linux-gnu/stage2-rustc/wasm32-wasip1-threads/release/rustc-main.wasm"

die() { echo "error: $*" >&2; exit 1; }

need() {
  for f in "$@"; do [ -e "$f" ] || die "missing $f (run scripts/build.sh first?)"; done
}

# select_target TRIPLE: sets TARGET, SYSROOT, WINLIB, MINGW_LIB, MINGW_GCC and
# RS_OBJECTS (1 if the target's sysroot carries rsbegin.o/rsend.o).
#
# The *-windows-gnu targets use Debian's gcc-mingw-w64-x86-64 / -i686 runtime.
# Use the *-win32* gcc directory explicitly: a *-posix* one sits next to it and
# has different libgcc/libgcc_eh, so "the first match" is not safe.
#
# aarch64-pc-windows-gnullvm uses llvm-mingw's aarch64-w64-mingw32/lib (UCRT,
# LLVM libunwind, no libgcc), so MINGW_GCC is empty and there are no
# rsbegin.o/rsend.o: the target's self-contained objects are crt2.o only.
#
# The standard library is looked up in the install tree (dist) first, then in
# the stage1 sysroot, where `x.py build --stage 1 library --target TRIPLE`
# leaves it (a target added after the last full install is only there).
select_target() {
  TARGET="$1"
  RS_OBJECTS=1
  case "$TARGET" in
    x86_64-pc-windows-gnu|i686-pc-windows-gnu)
      case "$TARGET" in x86_64*) MINGW_PREFIX=x86_64-w64-mingw32 ;; *) MINGW_PREFIX=i686-w64-mingw32 ;; esac
      MINGW_LIB="/usr/$MINGW_PREFIX/lib"
      MINGW_GCC="$(ls -d "/usr/lib/gcc/$MINGW_PREFIX"/*-win32 2>/dev/null | head -1)"
      ;;
    aarch64-pc-windows-gnullvm)
      MINGW_LIB="$LLVM_MINGW/aarch64-w64-mingw32/lib"
      MINGW_GCC=""
      RS_OBJECTS=0
      ;;
    *) die "unsupported TARGET '$TARGET' (x86_64-pc-windows-gnu, i686-pc-windows-gnu or aarch64-pc-windows-gnullvm)" ;;
  esac
  SYSROOT=""
  for s in "$RUST_SRC/dist" "$RUST_SRC/build/x86_64-unknown-linux-gnu/stage1"; do
    if [ -d "$s/lib/rustlib/$TARGET/lib" ]; then SYSROOT="$s"; break; fi
  done
  [ -n "$SYSROOT" ] || die "no $TARGET standard library under $RUST_SRC (run scripts/build.sh first?)"
  WINLIB="$SYSROOT/lib/rustlib/$TARGET/lib"
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

select_target "${TARGET:-x86_64-pc-windows-gnu}"
