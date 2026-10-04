#!/usr/bin/env python3
"""Run production Core lifecycle/SQLite/bridge checks without unrelated app tests."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
developer = subprocess.check_output(["xcode-select", "-p"], text=True).strip()
frameworks = developer + "/Library/Developer/Frameworks"
with tempfile.TemporaryDirectory(prefix="aisland-runtime-tests-") as directory:
    package = Path(directory)
    shutil.copytree(root / "Sources/OpenIslandCore", package / "Sources/OpenIslandCore")
    tests = package / "Tests/OpenIslandCoreTests"
    tests.mkdir(parents=True)
    for name in ["RuntimeLifecycleTests.swift", "MiniMaxCodeMetadataTests.swift", "MiniMaxCodeBridgeTests.swift", "MiniMaxCodeDesktopLivenessTests.swift", "MiniMaxCodeConversationPresenceTests.swift"]:
        shutil.copy2(root / "Tests/OpenIslandCoreTests" / name, tests / name)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "RuntimeVerification", platforms: [.macOS(.v14)], targets: [
    .target(name: "OpenIslandCore"),
    .testTarget(name: "OpenIslandCoreTests", dependencies: ["OpenIslandCore"])
])
''')
    command = ["swift", "test", "--package-path", str(package), "--enable-swift-testing"]
    if (Path(frameworks) / "Testing.framework").exists():
        command += ["-Xswiftc", "-F", "-Xswiftc", frameworks,
                    "-Xlinker", "-F" + frameworks, "-Xlinker", "-rpath", "-Xlinker", frameworks,
                    "-Xlinker", "-rpath", "-Xlinker", developer + "/Library/Developer/usr/lib",
                    "-Xswiftc", "-Xfrontend", "-Xswiftc", "-disable-cross-import-overlays"]
    raise SystemExit(subprocess.run(command, cwd=root).returncode)
