#!/usr/bin/env bash
# Download the wasmtime release used to run the compiler into $WORK/wasmtime.
# Needs a release that still has WASI threads (-Sthreads=y); v28.0.0 works,
# v50 reports "-Sthreads flag is no longer supported".
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
. "$here/env.sh"
if [ -x "$WASMTIME" ]; then echo "already have $("$WASMTIME" --version)"; exit 0; fi
mkdir -p "$WORK"
url="https://github.com/bytecodealliance/wasmtime/releases/download/${WASMTIME_VERSION}/wasmtime-${WASMTIME_VERSION}-x86_64-linux.tar.xz"
tmp="$(mktemp -d)"
curl -fsSL "$url" | tar -xJ -C "$tmp"
rm -rf "$WORK/wasmtime"
mv "$tmp"/wasmtime-* "$WORK/wasmtime"
rmdir "$tmp"
"$WASMTIME" --version
