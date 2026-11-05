#!/usr/bin/env python3
"""Safely raise the single bundled Noto Sans CJK fallback font in place.
Only the launcher-bundled OFL fallback font is modified, never the user .srom.
"""
import sys
from pathlib import Path
from fontTools.ttLib import TTFont

def main():
    path = Path(sys.argv[1])
    font = TTFont(str(path))
    if "CFF " not in font:
        raise SystemExit("Expected CFF OpenType fallback font")
    top = font["CFF "].cff.topDictIndex[0]
    old = list(top.FontMatrix)
    if len(old) != 6 or abs(float(old[0]) - 0.001) > 0.0001:
        raise SystemExit("Unexpected CFF font matrix: "+str(old))
    new = list(old)
    new[5] = round(float(new[5]) + 0.110, 6)
    top.FontMatrix = new
    tmp = path.with_suffix(".adjusted.otf")
    font.save(str(tmp))
    font.close()
    check = TTFont(str(tmp))
    actual = list(check["CFF "].cff.topDictIndex[0].FontMatrix)
    check.close()
    if abs(float(actual[5]) - float(new[5])) > 0.000001:
        raise SystemExit("Font baseline validation failed")
    tmp.replace(path)
    print("Single bundled fallback CJK font: baseline raised +110/1000 em")

if __name__ == "__main__":
    main()
