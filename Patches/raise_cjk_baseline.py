#!/usr/bin/env python3
"""Raise the visual baseline of Ruffle's packaged CJK fallback font slightly.

This is intentionally a tiny edit: the original OTF glyph outlines, advance
widths, Unicode cmap and x-position are untouched. Ruffle 0.7.1's FontFace uses
the font's ascender to place text. The original Noto CJK hhea ascender (1160)
is taller than its typographic ascender (880), making fallback text appear low
in some fixed-height SWF text fields.

Decrease ascender and decrease (make more negative) descender by the same
80 units out of 1000 unitsPerEm, retaining total line height. This raises
fallback glyphs by approx 1.2px for 15px text or 1.6px for 20px text.
It does not change SWF-embedded fonts.
"""
import array
import pathlib
import struct
import sys

MAGIC_CHECKSUM = 0xB1B0AFBA
RAISE_UNITS = 80
EXPECTED_HHEA = (1160, -288)

def sum32(data: bytes) -> int:
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)
    values = array.array("I")
    values.frombytes(data)
    if sys.byteorder == "little":
        values.byteswap()
    return sum(values) & 0xFFFFFFFF

def patch(font_path: pathlib.Path) -> None:
    data = bytearray(font_path.read_bytes())
    if data[:4] != b"OTTO":
        raise ValueError("Expected OpenType CFF font")
    number = struct.unpack_from(">H", data, 4)[0]
    tables = {}
    for i in range(number):
        offset = 12 + 16 * i
        tag, checksum, table_offset, length = struct.unpack_from(">4sIII", data, offset)
        if table_offset + length > len(data):
            raise ValueError(f"Invalid table extent: {tag!r}")
        tables[tag] = (offset, table_offset, length)
    if b"hhea" not in tables or b"head" not in tables:
        raise ValueError("Font missing hhea/head tables")

    hhea_record, hhea_offset, _ = tables[b"hhea"]
    _, head_offset, _ = tables[b"head"]
    ascender, descender = struct.unpack_from(">hh", data, hhea_offset + 4)
    if (ascender, descender) != EXPECTED_HHEA:
        raise ValueError(
            f"Unknown original Noto font metrics {(ascender, descender)}; refusing to patch"
        )
    # head version fields are 4+4+4, followed by magicNumber (4) then flags (2), unitsPerEm (2).
    units_per_em = struct.unpack_from(">H", data, head_offset + 18)[0]
    if units_per_em != 1000:
        raise ValueError(f"Unexpected unitsPerEm: {units_per_em}")

    struct.pack_into(">hh", data, hhea_offset + 4,
                     ascender - RAISE_UNITS, descender - RAISE_UNITS)
    # Recompute the affected table checksum in the OpenType table directory.
    hhea_length = tables[b"hhea"][2]
    struct.pack_into(">I", data, hhea_record + 4,
                     sum32(bytes(data[hhea_offset:hhea_offset + hhea_length])))
    # Overall OpenType checksumAdjustment must be calculated with this field zero.
    struct.pack_into(">I", data, head_offset + 8, 0)
    struct.pack_into(">I", data, head_offset + 8,
                     (MAGIC_CHECKSUM - sum32(bytes(data))) & 0xFFFFFFFF)
    if sum32(bytes(data)) != MAGIC_CHECKSUM:
        raise ValueError("OpenType checksumAdjustment verification failed")

    font_path.write_bytes(data)
    print(f"Font baseline adjusted: hhea ascent {ascender}->{ascender-RAISE_UNITS}; "
          f"descent {descender}->{descender-RAISE_UNITS}; "
          f"line height retained ({ascender-descender}), checksum OK.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 raise_cjk_baseline.py <NotoSansCJKsc-Regular.otf>")
    patch(pathlib.Path(sys.argv[1]))
