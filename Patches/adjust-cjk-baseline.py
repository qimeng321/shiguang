#!/usr/bin/env python3
"""Small experimental CJK glyph-baseline adjustment for the iOS test build.

This touches ONLY the bundled Noto Sans CJK fallback font. Embedded SWF fonts,
game assets, and the original downloaded file in the user's .srom are unchanged.
The original downloaded OTF is hash-verified in CI before this step.
"""
import sys
from pathlib import Path
from fontTools.ttLib import TTFont

def main():
    path = Path(sys.argv[1])
    font = TTFont(str(path))
    if "CFF " not in font:
        raise SystemExit("Expected CFF OTF font for the baseline experiment")
    top = font["CFF "].cff.topDictIndex[0]
    before = list(top.FontMatrix)
    if len(before) != 6 or abs(float(before[0]) - 0.001) > 0.0001:
        raise SystemExit(f"Unexpected CFF FontMatrix; keeping original font: {before}")
    # Raise fallback glyph outlines ~20 units at 1000 UPEM (~2% of an em).
    # Translation changes only the CFF glyph origin, not the stage or pointer mapping.
    after = list(before)
    after[5] = round(float(after[5]) + 0.020, 6)
    top.FontMatrix = after
    temp = path.with_suffix(".adjusted.otf")
    font.save(str(temp))
    font.close()
    check = TTFont(str(temp))
    saved = list(check["CFF "].cff.topDictIndex[0].FontMatrix)
    check.close()
    if abs(float(saved[5]) - float(after[5])) > 0.000001:
        raise SystemExit(f"Font baseline roundtrip failed: {saved}")
    temp.replace(path)
    print(f"TEST FONT: Noto Sans CJK fallback origin shifted +20/1000 em: {before} -> {saved}")

if __name__ == "__main__":
    main()
