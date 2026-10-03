#!/usr/bin/env python3
"""Verify the native welcome independently of unrelated app-test/toolchain gaps.

Copies production source/assets unchanged into a disposable library package;
never launches the app, starts bridges, or modifies real user preferences.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
developer = subprocess.check_output(["xcode-select", "-p"], text=True).strip()
frameworks = developer + "/Library/Developer/Frameworks"
with tempfile.TemporaryDirectory(prefix="aisland-onboarding-tests-") as directory:
    package = Path(directory)
    for target in ["OpenIslandCore", "OpenIslandApp"]:
        (package / "Sources" / target).mkdir(parents=True)
        (package / "Tests" / (target + "Tests")).mkdir(parents=True)
    for name in ["AgentHookIntent.swift", "AgentIntentStore.swift", "OnboardingPresentation.swift"]:
        shutil.copy2(root / "Sources/OpenIslandCore" / name, package / "Sources/OpenIslandCore" / name)
    for path in (root / "Sources/OpenIslandApp").glob("Onboarding*.swift"):
        shutil.copy2(path, package / "Sources/OpenIslandApp" / path.name)
    shutil.copy2(root / "Sources/OpenIslandApp/ResourceBundle.swift", package / "Sources/OpenIslandApp/ResourceBundle.swift")
    shutil.copytree(root / "Sources/OpenIslandApp/Resources/Onboarding", package / "Sources/OpenIslandApp/Resources/Onboarding")
    shutil.copy2(root / "Tests/OpenIslandCoreTests/OnboardingPresentationTests.swift", package / "Tests/OpenIslandCoreTests")
    shutil.copy2(root / "Tests/OpenIslandAppTests/OnboardingRuntimeTests.swift", package / "Tests/OpenIslandAppTests")
    (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "OnboardingVerification", platforms: [.macOS(.v14)], targets: [
    .target(name: "OpenIslandCore"),
    .target(name: "OpenIslandApp", dependencies: ["OpenIslandCore"], resources: [.process("Resources")]),
    .testTarget(name: "OpenIslandCoreTests", dependencies: ["OpenIslandCore"]),
    .testTarget(name: "OpenIslandAppTests", dependencies: ["OpenIslandApp", "OpenIslandCore"])
])
''')
    command = ["swift", "test", "--package-path", str(package), "--enable-swift-testing"]
    if (Path(frameworks) / "Testing.framework").exists():
        command += ["-Xswiftc", "-F", "-Xswiftc", frameworks,
                    "-Xlinker", "-F" + frameworks, "-Xlinker", "-rpath", "-Xlinker", frameworks,
                    "-Xlinker", "-rpath", "-Xlinker", developer + "/Library/Developer/usr/lib",
                    "-Xswiftc", "-Xfrontend", "-Xswiftc", "-disable-cross-import-overlays"]
    raise SystemExit(subprocess.run(command, cwd=root).returncode)
