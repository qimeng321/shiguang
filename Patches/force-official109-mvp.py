#!/usr/bin/env python3
"""Force the reference-compatible MVP WASM variant for a patched Ruffle Nightly.

This affects WASM feature selection, not the Ruffle renderer, screen DPR or
quality setting. Refuses to change an unfamiliar build rather than produce
an unbootable IPA.
"""
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    sys.exit("Usage: force-official109-mvp.py Resources/Ruffle/ruffle.js")
js = Path(sys.argv[1])
if js.name != "ruffle.js":
    sys.exit("Expected ruffle.js")
source = js.read_text(encoding="utf-8")
wasms = list(js.parent.glob("*.wasm"))
if len(wasms) < 2 or any(w.stat().st_size < 1_000_000 for w in wasms):
    sys.exit(f"Expected full MVP + extensions WASM build, got {len(wasms)}")
chunks = [p for p in js.parent.glob("core.ruffle.*.js")
          if "ruffle_web-wasm_mvp_bg.js" in p.read_text(encoding="utf-8")]
if len(chunks) != 1:
    sys.exit(f"Missing unique MVP JS chunk: {len(chunks)}")
pattern = re.compile(r"const\s+([A-Za-z_$][\w$]*)=\(await Promise\.all\(\[([^\]\n]{5,220})\]\)\)\.every\(Boolean\);")
matches = list(pattern.finditer(source))
matches = [m for m in matches if m.group(2).count("()") >= 3]
if len(matches) != 1:
    sys.exit(f"MVP feature selector not safely recognized ({len(matches)} matches)")
m = matches[0]
patched = source[:m.start()]+f'const {m.group(1)}=false;console.info("[B143] iOS MVP WASM selected; official renderer and DPR preserved");'+source[m.end():]
js.write_text(patched,encoding="utf-8")
assert "[B143] iOS MVP WASM selected" in js.read_text(encoding="utf-8")
print("[B143] Official Nightly MVP WASM selected; renderer, graphics pipeline, DPR unchanged")
