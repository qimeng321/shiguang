#!/usr/bin/env python3
"""B141 test-only selector: choose PR22908's already-built MVP WASM, not extensions.

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
forced = 'const n=false;console.info("[B141] Forced PR22908 MVP WebAssembly; bypass reference-types extension path");'
source = js.read_text(encoding="utf-8")
if source.count(original) != 1:
    sys.exit("Ruffle feature detection selector changed; do NOT patch this engine blindly")
if 'r.e(482).then(r.bind(r,482))' not in source or 'r(124)' not in source:
    sys.exit("MVP import path not found")
if source.count(forced) != 0:
    sys.exit("script already patched")
for f in ("core.ruffle.cd8f4a1bc1c3add46cea.js", "e08a99c6c84797fd830e.wasm"):
    if not (js.parent/f).is_file():
        sys.exit(f"MVP file missing: {f}")
core = (js.parent/"core.ruffle.cd8f4a1bc1c3add46cea.js").read_text(encoding="utf-8")
if "ruffle_web-wasm_mvp_bg.js" not in core or "__wbindgen_init_externref_table" in core:
    sys.exit("MVP JS module identity check failed")
js.write_text(source.replace(original, forced), encoding="utf-8")
assert js.read_text(encoding="utf-8").count(forced) == 1
print("PASS B141: forced MVP WASM selector; PR22908 core unchanged")
