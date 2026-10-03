#!/usr/bin/env python3
"""Build an isolated extraction of the production row and export demo PNGs."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, default=HERE.parents[2])
parser.add_argument("--output", type=Path)
args = parser.parse_args()
repo = args.source.resolve()
output = (args.output or repo / "output/verification/v0.1.1-intro-revision-3/native-rows").resolve()
output.mkdir(parents=True, exist_ok=True)
provenance = {"sourceRepository": str(repo), "sourceCommit": subprocess.check_output(
    ["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip(), "sources": [],
    "transformations": ["Only LanguageManager preference IO replaced with fixed zh-Hans language; drawing source unchanged",
                        "Bundle.appResources points to the isolated capture target's localization bundle",
                        "Private row and helper declarations remain in one compilation unit"]}

def read(path):
    data = (repo / path).read_bytes()
    return data.decode("utf-8"), hashlib.sha256(data).hexdigest()

def extract(path, start=None, end=None):
    text, checksum = read(path)
    first = text.index(start) if start else 0
    last = text.index(end, first) if end else len(text)
    selected = text[first:last]
    provenance["sources"].append({"path": path, "fileSHA256": checksum,
        "startLine": text[:first].count("\n") + 1,
        "endLine": text[:last].count("\n") + (0 if text[:last].endswith("\n") else 1),
        "extractionSHA256": hashlib.sha256(selected.encode()).hexdigest()})
    return selected

with tempfile.TemporaryDirectory(prefix="aisland-native-rows-") as temp:
    package = Path(temp)
    target = package / "Sources/NativeRows"
    target.mkdir(parents=True)
    panel = "Sources/OpenIslandApp/Views/IslandPanelView.swift"
    row = "import SwiftUI\n@preconcurrency import MarkdownUI\nimport OpenIslandCore\n"
    row += extract(panel, "private struct ContentHeightKey:", "// MARK: - Row Height Estimation")
    row += extract(panel, "private struct ConditionalDrawingGroup:", "// MARK: - Main island view")
    row += extract(panel, "private enum IslandSessionRowPresentation")
    row += "\n" + HERE.joinpath("capture.swift").read_text()
    (target / "main.swift").write_text(row)
    for path in ["Sources/OpenIslandApp/AgentSession+Presentation.swift", "Sources/OpenIslandApp/IslandDesignPalette.swift"]:
        (target / Path(path).name).write_text(extract(path))
    helpers = extract("Sources/OpenIslandApp/AppModelTypes.swift", "enum IslandSessionStateIndicator:", "enum IslandSessionGroup:")
    helpers += extract("Sources/OpenIslandApp/V6ClosedPillShape.swift", "enum V6Palette")
    helpers += extract("Sources/OpenIslandApp/AppModel.swift", "extension String {\n    var normalizedHexColorString:")
    (target / "Helpers.swift").write_text("import SwiftUI\nimport AppKit\n" + helpers)
    language = extract("Sources/OpenIslandApp/Localization/LanguageManager.swift")
    original_state = '''            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
'''
    original_init = '''        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "system"
        let lang = AppLanguage(rawValue: saved) ?? .system'''
    assert language.count(original_state) == 1 and language.count(original_init) == 1, "LanguageManager changed; review isolation transformation"
    language = language.replace(original_state, "").replace(original_init, "        let lang = AppLanguage.zhHans")
    assert "UserDefaults.standard" not in language, "Capture must not access preferences"
    (target / "LanguageManager.swift").write_text(language)
    (target / "ResourceBundle.swift").write_text("import Foundation\nextension Bundle { static var appResources: Bundle { .module } }\n")
    resources = target / "Resources"
    resources.mkdir()
    for folder in sorted((repo / "Sources/OpenIslandApp/Resources").glob("*.lproj")):
        shutil.copytree(folder, resources / folder.name)
        for file in sorted(folder.rglob("*")):
            if file.is_file():
                extract(str(file.relative_to(repo)))
    # The tool depends only on Core and MarkdownUI; no app executable target.
    manifest = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "NativeRowsCapture", defaultLocalization: "en", platforms: [.macOS(.v14)],
    dependencies: [.package(name: "IslandSource", path: %s),
                   .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1")],
    targets: [.executableTarget(name: "NativeRows", dependencies: [
        .product(name: "OpenIslandCore", package: "IslandSource"),
        .product(name: "MarkdownUI", package: "swift-markdown-ui")], resources: [.process("Resources")])])
''' % json.dumps(str(repo))
    (package / "Package.swift").write_text(manifest)
    subprocess.run(["swift", "build", "--package-path", str(package), "--product", "NativeRows", "-c", "debug"], check=True)
    executable = package / ".build/debug/NativeRows"
    subprocess.run([str(executable), str(output)], check=True)
    for path in sorted((repo / "Sources/OpenIslandCore").glob("*.swift")):
        provenance["sources"].append({"path": str(path.relative_to(repo)), "fileSHA256": hashlib.sha256(path.read_bytes()).hexdigest(), "usage": "compiled OpenIslandCore dependency; no runtime services instantiated"})
    dependencies = package / "Package.resolved"
    if dependencies.exists():
        provenance["resolvedPackages"] = json.loads(dependencies.read_text())
    provenance["artifacts"] = [{"file": path.name, "SHA256": hashlib.sha256(path.read_bytes()).hexdigest()}
                               for path in sorted(output.glob("native-row-*"))]
    (output / "native-row-provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
print(f"Native row assets and provenance: {output}")
