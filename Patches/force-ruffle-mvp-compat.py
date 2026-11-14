#!/usr/bin/env python3
"""B142 standalone iOS repair: choose dynamically built MVP WASM, not extensions.

The B140 iOS WebKit failure is WebAssembly.Table.prototype.grow on the
extensions module. This does not change Rust/GC logic or the game SWFs.
Refuse to patch an unknown/minified Ruffle version.
"""
import sys
from pathlib import Path

if len(sys.argv) != 2:
    sys.exit("usage: force-ruffle-mvp-compat.py <Ruffle/ruffle.js>")
js = Path(sys.argv[1])
if js.name != "ruffle.js":
    sys.exit("expected ruffle.js")
original = 'const n=(await Promise.all([Ke(),Ye(),Qe(),Ge(),Ze()])).every(Boolean);'
forced = 'const n=false;console.info("[B142] Use iOS-compatible MVP WebAssembly from GC+GPU repaired Ruffle core");'
source = js.read_text(encoding="utf-8")
if source.count(original) != 1:
    sys.exit("Ruffle feature detection selector changed; do NOT patch this engine blindly")
if 'r.e(482).then(r.bind(r,482))' not in source or 'r(124)' not in source:
    sys.exit("MVP import path not found")
if source.count(forced) != 0:
    sys.exit("script already patched")
wasms = list(js.parent.glob("*.wasm"))
if len(wasms) < 2 or any(p.stat().st_size < 1_000_000 for p in wasms):
    sys.exit("Expected complete extension and MVP WASM binaries")
cores = list(js.parent.glob("core.ruffle.*.js"))
mvp = [p for p in cores if "ruffle_web-wasm_mvp_bg.js" in p.read_text(encoding="utf-8")]
if len(mvp) != 1:
    sys.exit(f"Expected exactly one MVP JS chunk, got {len(mvp)}")
core = mvp[0].read_text(encoding="utf-8")
if "__wbindgen_init_externref_table" in core:
    sys.exit("MVP chunk unexpectedly uses externref initialization")
js.write_text(source.replace(original, forced), encoding="utf-8")
assert js.read_text(encoding="utf-8").count(forced) == 1
print("PASS B142: forced dynamically hashed MVP JS/WASM, no weakened checks")
