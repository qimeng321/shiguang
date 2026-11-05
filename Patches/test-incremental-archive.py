#!/usr/bin/env python3
"""Static structure and ZIP layout checks, not a substitute for on-device testing."""
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
    "let sorted = checked.paths.filter",
):
    assert requirement in source, requirement
assert source.index("JSONEncoder().encode(journal).write") < source.index("for (i, path) in sorted.enumerated()"), "Journal must precede file mutation"
assert "GameIncrementalUpdater.recoverIfNeeded" in model
assert "prepareIncrementalUpdate" in model and "installPreparedIncrementalUpdate" in model
assert "incrementalUpdatePanel" in app and "showingDeltaPicker" in app
assert "importMobilePatch" in model
with tempfile.TemporaryDirectory() as temp:
    path = Path(temp) / "incremental.zip"
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("config/dll.xml", '<taomee><ext><item path="dll/NieoCore.swf?2026110401" ver="2026110401" /></ext></taomee>')
        archive.writestr("dll/NieoCore.swf", b"FWS" + b"\x00"*64)
        archive.writestr("resource/map/999.swf", b"FWS" + b"\x00"*64)
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        assert len(names) == 3 and "Client.swf" not in names
        assert names.issuperset({"config/dll.xml", "dll/NieoCore.swf"})
        assert archive.testzip() is None
        assert re.search(r'ver="2026110401"', archive.read("config/dll.xml").decode("utf-8"))
print("PASS: incremental updater structure and representative ZIP layout")
