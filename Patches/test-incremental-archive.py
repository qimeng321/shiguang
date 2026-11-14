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

# Flexibility requirements: login modules, SGCore and unrelated assets can
# co-exist in a delta, including same-revision and resource-only packages.
for fragment in (
    'path == "Client.swf" || path == "index.html"',
    'if let config = entries["config/dll.xml"]',
    'let target = checked.targetRevision ?? current',
    'if let target = checked.targetRevision',
    'let installedRevision = LaunchDiagnostics.coreRevision',
    'guard !paths.isEmpty',
    'permittedDirectory(prefix)',
    '"swf", "xml", "json"',
    '"js", "mjs", "css", "wasm"',
    'skipCRC32: false',
):
    assert fragment in source, fragment
assert 'path.hasPrefix("login/")' not in source
assert 'path.hasPrefix("assets/")' not in source
assert 'presentCores.count == 1' not in source
assert 'if current == checked.targetRevision' not in source
assert 'corePath: checked.corePath' not in source
assert 'journal.committed = true' in source
assert 'if path == "Client.swf" || path == "index.html"' in source
assert 'entry.type == .file' in source
assert '&& !$0.lowercased().hasSuffix(".app")' in source

def fixture(path, files):
    with zipfile.ZipFile(path, "w") as archive:
        for filename, contents in files.items():
            archive.writestr(filename, contents)
    with zipfile.ZipFile(path) as archive:
        assert set(archive.namelist()) == set(files)
        assert archive.testzip() is None

with tempfile.TemporaryDirectory() as temp:
    for suffix in (".zip", ".srom"):
        # Match the user's actual five-entry SGCore/login/ice-cave update.
        revision = "2026111405"
        files = {
            "config/dll.xml": f'<taomee><ext><item path="dll/SGCore.swf?{revision}" ver="{revision}"/></ext></taomee>',
            "dll/SGCore.swf": b"FWS" + b"\x00" * 64,
            "login/Login.swf": b"FWS" + b"\x00" * 64,
            "module/com/robot/module/app/SpriteFusionPanel.swf": b"FWS" + b"\x00" * 64,
            "module/com/robot/module/game/IcicleGame.swf": b"FWS" + b"\x00" * 64,
        }
        fixture(Path(temp) / ("sgcore-login" + suffix), files)
        assert re.search(r'ver="\d{10}"', files["config/dll.xml"])
        # Legacy core replacement is still allowed.
        fixture(Path(temp) / ("legacy" + suffix), {
            "config/dll.xml": '<item path="dll/NieoCore.swf?2026110401" ver="2026110401"/>',
            "dll/NieoCore.swf": b"FWS" + b"\x00" * 64,
        })
        # No core or version XML required to update normal game resources.
        fixture(Path(temp) / ("resources-only" + suffix), {
            "resource/map/999.swf": b"FWS" + b"\x00" * 64,
            "login/Login.swf": b"FWS" + b"\x00" * 64,
            "assets/game.json": "{}",
        })
        # Config can be updated without requiring a core SWF in the ZIP.
        fixture(Path(temp) / ("xml-only" + suffix), {
            "config/dll.xml": '<item path="dll/SGCore.swf?2026111405" ver="2026111405"/>',
        })
    full = Path(temp) / "complete.srom"
    fixture(full, {"Client.swf": b"FWS" + b"\x00" * 64, "index.html": "<html></html>"})
    assert 'throw GameIncrementalError.fullGamePackage' in source
    assert 'private static let maxArchiveBytes' in source

print("PASS: flexible SGCore/login ZIP/SROM deltas; no XML/core lock; same-version support; rollback and full-import guard")
