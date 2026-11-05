#!/usr/bin/env python3
"""Build two alternative licensed Noto CJK fallback fonts, keeping original."""
import sys
from pathlib import Path
from fontTools.ttLib import TTFont

def main():
    original = Path(sys.argv[1])
    for units, suffix in ((110, "Lift110"), (170, "Lift170")):
        font = TTFont(str(original))
        if "CFF " not in font:
            raise SystemExit("Expected CFF OpenType fallback font")
        top = font["CFF "].cff.topDictIndex[0]
        before = list(top.FontMatrix)
        if len(before) != 6 or abs(float(before[0]) - 0.001) > 0.0001:
            raise SystemExit(f"Unexpected CFF matrix: {before}")
        after = list(before)
        after[5] = round(float(before[5]) + units / 1000, 6)
        top.FontMatrix = after
        output = original.with_name("NotoSansCJKsc-" + suffix + ".otf")
        font.save(str(output))
        font.close()
        check = TTFont(str(output))
        value = float(check["CFF "].cff.topDictIndex[0].FontMatrix[5])
        check.close()
        if abs(value - after[5]) > 0.000001:
            raise SystemExit(f"FontMatrix verification failed: {output}")
        print(f"Verified {output.name}: CFF baseline +{units}/1000")

if __name__ == "__main__":
    main()
