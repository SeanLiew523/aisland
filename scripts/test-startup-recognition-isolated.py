#!/usr/bin/env python3
"""Test production startup coordinator/Core against synthetic stores only.

Does not create AppModel, launch source apps, read user transcripts or defaults.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="aisland-startup-recognition-") as directory:
    package = Path(directory)
    shutil.copytree(root / "Sources/OpenIslandCore", package / "Sources/OpenIslandCore")
    app = package / "Sources/OpenIslandApp"
    app.mkdir(parents=True)
    shutil.copy2(root / "Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift", app)
    for target, names in {
        "OpenIslandCoreTests": ["ClaudeSessionRegistryTests.swift"],
        "OpenIslandAppTests": ["StartupSessionDiscoveryTests.swift", "StartupLiveMonitoringTests.swift"],
    }.items():
        tests = package / "Tests" / target
        tests.mkdir(parents=True)
        for name in names:
            shutil.copy2(root / "Tests" / target / name, tests)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "StartupRecognitionChecks", platforms: [.macOS(.v14)], targets: [
    .target(name: "OpenIslandCore"),
    .target(name: "OpenIslandApp", dependencies: ["OpenIslandCore"]),
    .testTarget(name: "OpenIslandCoreTests", dependencies: ["OpenIslandCore"]),
    .testTarget(name: "OpenIslandAppTests", dependencies: ["OpenIslandApp", "OpenIslandCore"])
])
''')
    command = ["zsh", str(root / "scripts/test-clt.sh"), "--package-path", str(package),
               "--disable-xctest", "-Xswiftc", "-Xfrontend", "-Xswiftc", "-disable-cross-import-overlays"]
    raise SystemExit(subprocess.run(command, cwd=root).returncode)
