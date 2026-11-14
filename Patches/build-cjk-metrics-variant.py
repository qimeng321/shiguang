#!/usr/bin/env python3
"""Build a conservative CJK fallback-font metrics experiment for B-only Ruffle.

Input is the existing +0.110em Noto Sans CJK SC OTF after the legacy baseline
shift. Do NOT alter CFF glyph outlines, CFF FontMatrix, horizontal metrics,
family name, cmap or user-supplied .srom assets. The optimized variant shifts
the nominal baseline 90 design units upward while preserving line heights.

The legacy OTF remains in fonts/ and can be selected as an exact fallback.
"""
import sys
from pathlib import Path
from fontTools.ttLib import TTFont

DELTA = 90
EXPECTED_HHEA = (1160, -288, 0)
EXPECTED_TYPO = (880, -120, 0)

def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: build-cjk-metrics-variant.py original.otf optimized.otf")
    src, dest = map(Path, sys.argv[1:])
    original = TTFont(str(src))
    assert original["head"].unitsPerEm == 1000, "Unexpected unitsPerEm"
    assert "CFF " in original, "Expected Noto CJK OTF"
    matrix = list(original["CFF "].cff.topDictIndex[0].FontMatrix)
    assert len(matrix) == 6 and abs(float(matrix[5]) - 0.110) < 0.00001, matrix
    hhea, os2 = original["hhea"], original["OS/2"]
    expected_hhea = (hhea.ascent, hhea.descent, hhea.lineGap)
    expected_typo = (os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap)
    assert expected_hhea == EXPECTED_HHEA, expected_hhea
    assert expected_typo == EXPECTED_TYPO, expected_typo

    # Keep hhea and typographic line heights identical to the original so
    # Flash multiline text does not reflow. Only the baseline position moves.
    hhea.ascent -= DELTA
    hhea.descent -= DELTA
    os2.sTypoAscender -= DELTA
    os2.sTypoDescender -= DELTA
    # Retain usWinAscent/Descent to avoid reducing clipping bounds. Do not
    # toggle USE_TYPO_METRICS: that would change line-height semantics.
    dest.parent.mkdir(parents=True, exist_ok=True)
    original.save(str(dest))
    original.close()

    check = TTFont(str(dest))
    newh, newos = check["hhea"], check["OS/2"]
    assert (newh.ascent, newh.descent, newh.lineGap) == (1070, -378, 0)
    assert (newos.sTypoAscender, newos.sTypoDescender, newos.sTypoLineGap) == (790, -210, 0)
    assert list(check["CFF "].cff.topDictIndex[0].FontMatrix) == matrix
    assert newh.ascent - newh.descent == EXPECTED_HHEA[0] - EXPECTED_HHEA[1]
    assert newos.sTypoAscender - newos.sTypoDescender == EXPECTED_TYPO[0] - EXPECTED_TYPO[1]
    assert newos.usWinAscent == 1160 and newos.usWinDescent == 288
    check.close()
    print("B-only Noto CJK optimized vertical metrics: hhea (1070,-378), typo (790,-210), glyphs unchanged")

if __name__ == "__main__":
    main()
