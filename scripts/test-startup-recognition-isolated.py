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
    # Execute the two exact production desktop-liveness loops. Only app
    # availability queries become explicit fixture inputs; stale guards and
    # source/tool filtering are unchanged. No NSRunningApplication is queried.
    monitor = (root / "Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift").read_text()
    start = monitor.index("        let isZcodeRunning = Self.isZcodeAppRunning()")
    end = monitor.index("        // Hermes hooks own task state", start)
    loops = monitor[start:end].replace("Self.isZcodeAppRunning()", "zcodeRunning").replace("Self.isWorkbuddyAppRunning()", "workbuddyRunning")
    fixture = "import Foundation\nimport OpenIslandCore\nstruct DesktopCacheLivenessFixture {\n"
    for name in ["zcodeAppStalenessTimeout", "workbuddyAppStalenessTimeout"]:
        fixture += next(line.split("//")[0] for line in monitor.splitlines() if "private static let " + name + ":" in line) + "\n"
    fixture += "func aliveSessionIDs(for sessions: [AgentSession], zcodeRunning: Bool, workbuddyRunning: Bool) -> Set<String> {\nvar aliveIDs = Set<String>()\n"
    fixture += loops + "return aliveIDs\n}\n}\n"
    (app / "DesktopCacheLivenessFixture.swift").write_text(fixture)
    for target, names in {
        "OpenIslandCoreTests": ["ClaudeSessionRegistryTests.swift", "StartupDiscoveryStreamingTests.swift", "ClaudeTranscriptDiscoveryTests.swift"],
        "OpenIslandAppTests": ["StartupSessionDiscoveryTests.swift", "StartupLiveMonitoringTests.swift"],
    }.items():
        tests = package / "Tests" / target
        tests.mkdir(parents=True)
        for name in names:
            shutil.copy2(root / "Tests" / target / name, tests)
    shutil.copy2(root / "Tests/Fixtures/StartupDesktopCacheLivenessTests.swift", package / "Tests/OpenIslandAppTests")
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
