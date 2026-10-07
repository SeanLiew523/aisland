#!/usr/bin/env python3
"""Run production Core lifecycle/SQLite/bridge checks without unrelated app tests."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
developer = subprocess.check_output(["xcode-select", "-p"], text=True).strip()
frameworks = developer + "/Library/Developer/Frameworks"

def source_block(path, signature):
    """Execute the exact production pure method, rather than a copied algorithm."""
    source = (root / path).read_text()
    if source.count(signature) != 1:
        raise ValueError(f"Expected one production block: {signature}")
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    for end in range(opening + 1, len(source)):
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        if depth == 0:
            return source[start:end + 1].removeprefix("private ")
    raise ValueError(f"Unclosed production block: {signature}")

with tempfile.TemporaryDirectory(prefix="aisland-runtime-tests-") as directory:
    package = Path(directory)
    shutil.copytree(root / "Sources/OpenIslandCore", package / "Sources/OpenIslandCore")
    tests = package / "Tests/OpenIslandCoreTests"
    tests.mkdir(parents=True)
    for name in ["RuntimeLifecycleTests.swift", "MiniMaxCodeMetadataTests.swift", "MiniMaxCodeBridgeTests.swift", "MiniMaxCodeDesktopLivenessTests.swift", "MiniMaxCodeConversationPresenceTests.swift"]:
        shutil.copy2(root / "Tests/OpenIslandCoreTests" / name, tests / name)
    shutil.copy2(root / "Tests/Fixtures/MiniMaxCodeDisplayBucketTests.swift", tests)
    # The host supplies only state and a fixed display threshold. It never
    # constructs AppModel or reads UserDefaults/source apps. Ranking, identity
    # selection and primary/overflow filtering are the production methods.
    monitor = "Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift"
    model = "Sources/OpenIslandApp/AppModel.swift"
    presentation = "Sources/OpenIslandApp/AgentSession+Presentation.swift"
    host = "import Foundation\n@testable import OpenIslandCore\n"
    host += source_block(presentation, "enum IslandSessionPresence") + "\n"
    host += "extension AgentSession {\n"
    host += "static let islandActivityThreshold: TimeInterval = 20 * 60\n"
    host += "static let staleCompletedDisplayThreshold: TimeInterval = 5 * 60\n"
    for signature in ["var isSubagentSession", "var islandActivityDate", "func islandPresence(", "func isStaleCompletedForIsland("]:
        host += source_block(presentation, signature) + "\n"
    host += "}\nstruct MiniMaxDisplayMonitorFixture {\n"
    for signature in ["func liveAttachmentKey(", "func normalizedPathForMatching(", "func normalizedTTYForMatching(", "func supportedTerminalApp("]:
        host += source_block(monitor, signature) + "\n"
    host += "}\nstruct MiniMaxDisplayThresholdFixture { var seconds: TimeInterval = 300 }\n"
    host += "struct MiniMaxDisplayBucketFixture {\nvar state: SessionState\n"
    host += "let monitoring = MiniMaxDisplayMonitorFixture()\n"
    host += "let completedStaleThreshold = MiniMaxDisplayThresholdFixture()\n"
    for signature in ["private func computeSessionBuckets(", "private func displayPriority("]:
        host += source_block(model, signature) + "\n"
    host += "}\n"
    (tests / "MiniMaxDisplayProductionFixture.swift").write_text(host)
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
