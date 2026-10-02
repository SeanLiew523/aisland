#!/usr/bin/env python3
"""Run the native glyph tests alone when unrelated app tests cannot compile."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
developer = subprocess.check_output(["xcode-select", "-p"], text=True).strip()
frameworks = developer + "/Library/Developer/Frameworks"

with tempfile.TemporaryDirectory(prefix="bloub-tests-") as directory:
    package = Path(directory)
    sources = package / "Sources/OpenIslandApp"
    tests = package / "Tests/OpenIslandAppTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for name in ["UnifiedBars.swift", "BloubStatusGlyph.swift"]:
        shutil.copy2(root / "Sources/OpenIslandApp/Views" / name, sources / name)
    shutil.copy2(root / "Tests/OpenIslandAppTests/BloubStatusGlyphTests.swift", tests)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BloubVerification", platforms: [.macOS(.v14)],
    products: [.library(name: "OpenIslandApp", targets: ["OpenIslandApp"])],
    targets: [.target(name: "OpenIslandApp"),
              .testTarget(name: "OpenIslandAppTests", dependencies: ["OpenIslandApp"])])
''')
    command = ["swift", "test", "--package-path", str(package), "--enable-swift-testing"]
    if (Path(frameworks) / "Testing.framework").exists():
        command += ["-Xswiftc", "-F", "-Xswiftc", frameworks,
                    "-Xlinker", "-F" + frameworks,
                    "-Xlinker", "-rpath", "-Xlinker", frameworks,
                    "-Xlinker", "-rpath", "-Xlinker", developer + "/Library/Developer/usr/lib",
                    "-Xswiftc", "-Xfrontend", "-Xswiftc", "-disable-cross-import-overlays"]
    result = subprocess.run(command, cwd=root)
    raise SystemExit(result.returncode)
