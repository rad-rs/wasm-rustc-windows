#!/usr/bin/env bash
# Shrink the compiler wasm with binaryen's wasm-opt (apt: binaryen).
#
#   scripts/optimize.sh [IN [OUT]]
#
# IN defaults to the freshly built rustc-main.wasm, OUT to $WORK/rustc_opt.wasm.
#   OPT=-Os            optimisation level passed to wasm-opt (default -Os; -Oz CRASHES wasm-opt on this module, -O2 crashes binaryen 120)
#   WASM_OPT=wasm-opt  which binaryen to use (binaryen 133 was used for the shipped variant)
#   SIZES=1            also print gzip -9 and brotli -q 11 sizes (brotli on 100+ MB takes minutes)
#
# Notes (see README "Size" for the measurements):
#  - wasm-opt SEGFAULTS with the default 8 MB stack on this module; it needs the
#    1 GB stack set below. It also uses about 6 GB of RAM and several minutes.
#  - wasm-opt needs --enable-* flags for the features the module uses. They normally
#    come from the module's own target_features section, but `rust.strip = true` (set in
#    config/bootstrap.toml.in) strips that section, so the default list below is used when
#    the module no longer declares its features. Override with FEATURES="--enable-...".
#  - the optimised compiler must still be tested (scripts/test-hello.sh and
#    test-gui.sh with COMPILER_WASM=<OUT>) before it is shipped.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$here/env.sh"
IN="${1:-$RUSTC_WASM}"
OUT="${2:-$WORK/rustc_opt.wasm}"
WASM_OPT="${WASM_OPT:-wasm-opt}"
command -v "$WASM_OPT" >/dev/null || die "$WASM_OPT not found (apt-get install binaryen, or set WASM_OPT)"
need "$IN"
ulimit -s 1048576 || true

DEFAULT_FEATURES="--enable-threads --enable-mutable-globals --enable-nontrapping-float-to-int --enable-bulk-memory --enable-sign-ext --enable-reference-types --enable-multivalue"
if [ -n "${FEATURES:-}" ]; then
  features="$FEATURES"
elif declared="$("$WASM_OPT" "$IN" --print-features -o /dev/null 2>/dev/null)" && [ -n "$declared" ]; then
  features="$declared"                     # the module declares its features
else
  features="$DEFAULT_FEATURES"             # stripped module: use the known list
fi
echo "$($WASM_OPT --version): ${OPT:--Os} --strip-debug --strip-producers, features: $(echo $features)"
# shellcheck disable=SC2086
"$WASM_OPT" "$IN" $features "${OPT:--Os}" --strip-debug --strip-producers -o "$OUT"

echo "in : $(stat -c %s "$IN") bytes"
echo "out: $(stat -c %s "$OUT") bytes ($OUT)"
if [ "${SIZES:-0}" = 1 ]; then
  echo "gzip -9   : $(gzip -9 -c "$OUT" | wc -c) bytes"
  command -v brotli >/dev/null && echo "brotli -11: $(brotli -q 11 -c "$OUT" | wc -c) bytes"
fi
