# Local workaround: C++ wrapper target

On the tested base, `rustc_llvm/build.rs` compiled `llvm-wrapper/*.cpp` with
`--target=wasm32-wasi` (non-threads), selecting libc++ headers without
`<shared_mutex>`. The workaround used is `scripts/cxxw.sh`, a clang++ wrapper
that rewrites the flag to `--target=wasm32-wasi-threads`, plus this one-line
change in `compiler/rustc_llvm/build.rs` (the `if target.contains("wasi")` block):

```diff
-        cfg.compiler(wasi_sdk_path.join("bin").join(format!("{target}-clang++")));
+        cfg.compiler(PathBuf::from("/absolute/path/to/scripts/cxxw.sh"));
```

`cxxw.sh` uses `$WASI_SDK_PATH`. This is a workaround, not a fix: the root cause
was not identified.
