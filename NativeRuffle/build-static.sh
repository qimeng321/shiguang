#!/bin/bash
# Build a true native Rust/Metal Ruffle static library for the experimental
# SwiftUI launcher. This runs only on macOS with the iOS SDK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -rf "$RUNNER_TEMP/ruffle-ios-embed"
git clone https://github.com/madsmtm/ruffle-ios.git "$RUNNER_TEMP/ruffle-ios-embed"
cd "$RUNNER_TEMP/ruffle-ios-embed"
git checkout --detach c3489324265221ff5089442797be671df14fdcdb
cp "$ROOT/NativeRuffle/bridge.rs" src/shiguang_bridge.rs
printf '\nmod shiguang_bridge;\n' >> src/lib.rs
cat >> Cargo.toml <<'EOF'

[lib]
crate-type = ["staticlib"]
EOF
export CARGO_INCREMENTAL=0
export CARGO_BUILD_JOBS=4
# Keep Rust/C native dependencies at the same minimum OS as the Swift app.
# Otherwise assembly objects compiled with Xcode 26.6 can require iOS 26.5.
export IPHONEOS_DEPLOYMENT_TARGET=16.0
export CFLAGS_aarch64_apple_ios="-miphoneos-version-min=16.0"
export CXXFLAGS_aarch64_apple_ios="-miphoneos-version-min=16.0"
rustup toolchain install nightly --profile minimal --component rust-src --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios --lib --locked
OUT="$ROOT/NativeRuffle/lib"
mkdir -p "$OUT"
cp target/aarch64-apple-ios/release/libruffle_ios.a "$OUT/libruffle_ios.a"
test "$(stat -f%z "$OUT/libruffle_ios.a")" -gt 1000000
# Apple's system nm may not understand bitcode produced by Rust nightly's
# newer LLVM (error: Unknown attribute kind 105). The actual linker validates
# all FFI symbols when it links the Swift app below, so do not fail here.
test -s "$OUT/libruffle_ios.a"
echo "FFI export validation deferred to Xcode linker (avoids incompatible system nm)."
echo "Genuine native Rust/Metal Ruffle static library ready: $(du -h "$OUT/libruffle_ios.a")"
