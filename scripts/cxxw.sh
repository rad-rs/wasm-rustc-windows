#!/bin/bash
# Local workaround: the cc crate/bootstrap pass --target=wasm32-wasi (non-threads),
# which selects libc++ headers without <shared_mutex>. Force the threads triple.
args=()
for a in "$@"; do
  if [ "$a" = "--target=wasm32-wasi" ]; then a="--target=wasm32-wasi-threads"; fi
  args+=("$a")
done
exec ${WASI_SDK_PATH:?set WASI_SDK_PATH}/bin/wasm32-wasip1-threads-clang++ "${args[@]}"
