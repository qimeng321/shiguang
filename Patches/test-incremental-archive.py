#!/usr/bin/env python3
"""Static safety and ZIP-backed .zip/.srom fixture checks, not real iOS runtime tests."""
from pathlib import Path
import re
import zipfile
import tempfile

source = Path("Sources/GameIncrementalUpdater.swift").read_text()
model = Path("Sources/LauncherModel.swift").read_text()
app = Path("Sources/ShiguangLauncherApp.swift").read_text()

for requirement in (
    "func recoverIfNeeded(gameRoot:",
    "journal.committed = true",
    "skipCRC32: false",
    "ensureSafeAncestors",
    "guard entry.type == .file",
    "SHA256()",
    "case .downgrade",
    "case .upToDate",
    "case .unsafeFile",
    "case .fullGamePackage",
    "let sorted = checked.paths.filter",
    '["zip", "srom"].contains(url.pathExtension.lowercased())',
    'signature.starts(with: [0x50, 0x4B, 0x03, 0x04])',
):
    assert requirement in source, requirement

assert source.index("JSONEncoder().encode(journal).write") < source.index(
    "for (i, path) in sorted.enumerated()"
), "Journal must precede file mutation"
assert "GameIncrementalUpdater.recoverIfNeeded" in model
assert "prepareIncrementalUpdate" in model and "installPreparedIncrementalUpdate" in model
assert '["zip", "srom"].contains(source.pathExtension.lowercased())' in model
assert '["zip", "srom"].contains($0.pathExtension.lowercased())' in app
assert "incrementalUpdatePanel" in app and "showingDeltaPicker" in app
assert "importMobilePatch" in model
assert 'Text("1.06 新功能")' not in app and 'Text("测试功能")' not in app
assert app.count(".fill(isSelected ? blue : Color.white)") >= 2

# Confirm both supported core names are included in *each* code-path:
# archive recognition, exact matching XML target revision, and safe rollback.
assert 'let allowedCores = ["dll/SGCore.swf", "dll/NieoCore.swf"]' in source
assert 'entries["config/dll.xml"]' in source
assert 'presentCores.count == 1' in source
assert 'xml.contains(corePath + "?" + value)' in source
assert 'let corePath: String' in source
assert 'corePath: checked.corePath' in source
assert 'path == "dll/SGCore.swf" || path == "dll/NieoCore.swf"' in source
assert 'guard value.count == 10' in source
assert 'if current > checked.targetRevision' in source

with tempfile.TemporaryDirectory() as temp:
    for suffix in (".zip", ".srom"):
        for core, revision in [("SGCore", "2026111306"), ("NieoCore", "2026110401")]:
            core_path = f"dll/{core}.swf"
            path = Path(temp) / (f"{core}-incremental" + suffix)
            xml = f'<taomee><ext><item path="{core_path}?{revision}" ver="{revision}" /></ext></taomee>'
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("config/dll.xml", xml)
                archive.writestr(core_path, b"FWS" + b"\\x00" * 64)
                archive.writestr("resource/map/999.swf", b"FWS" + b"\\x00" * 64)
            with zipfile.ZipFile(path) as archive:
                names = set(archive.namelist())
                assert len(names) == 3 and "Client.swf" not in names
                assert names.issuperset({"config/dll.xml", core_path})
                assert archive.testzip() is None
                loaded = archive.read("config/dll.xml").decode("utf-8")
                assert f'{core_path}?{revision}' in loaded
                assert re.search(r'ver="\\d{10}"', loaded)
    # Complete game packs and unrelated native resources must not pass
    # through the incremental (partial-merge) importer.
    full_path = Path(temp) / "full.srom"
    with zipfile.ZipFile(full_path, "w") as archive:
        archive.writestr("Client.swf", b"FWS" + b"\\x00" * 64)
        archive.writestr("index.html", "<html></html>")
    with zipfile.ZipFile(full_path) as archive:
        assert "Client.swf" in archive.namelist()
    assert 'path == "Client.swf"' in source
    assert 'throw GameIncrementalError.fullGamePackage' in source
    assert 'if parent == "config" { return path == "config/dll.xml" }' in source

print("PASS: SGCore + legacy NieoCore ZIP/SROM fixtures, CRC32, XML-bound revision, safe rollback, full-package guard")
