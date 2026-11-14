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
rustup toolchain install nightly --profile minimal --component rust-src --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios --lib --locked
OUT="$ROOT/NativeRuffle/lib"
mkdir -p "$OUT"
cp target/aarch64-apple-ios/release/libruffle_ios.a "$OUT/libruffle_ios.a"
test "$(stat -f%z "$OUT/libruffle_ios.a")" -gt 1000000
nm -g "$OUT/libruffle_ios.a" > "$RUNNER_TEMP/shiguang-rust-symbols.txt"
grep -Fq '_shiguang_native_player_create' "$RUNNER_TEMP/shiguang-rust-symbols.txt" || {
  echo 'ERROR: native FFI export missing' >&2
  exit 1
}
echo "Genuine native Rust/Metal Ruffle static library ready: $(du -h "$OUT/libruffle_ios.a")"
