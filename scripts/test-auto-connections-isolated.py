#!/usr/bin/env python3
"""Run actual automatic-connection Core/coordinator sources with isolated fixtures.

Does not launch an App/source UI, install user hooks or build an App bundle.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
# Build a CLI callback helper only; no App bundle or source runtime is launched.
subprocess.run(["swift", "build", "--product", "OpenIslandHooks"], cwd=root, check=True, stdout=subprocess.DEVNULL)
bin_dir = subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip()
import os
environment = dict(os.environ, AISLAND_TEST_HOOKS_BINARY=str(Path(bin_dir) / "OpenIslandHooks"))
with tempfile.TemporaryDirectory(prefix="aisland-auto-connections-tests-") as directory:
    package = Path(directory)
    shutil.copytree(root / "Sources/OpenIslandCore", package / "Sources/OpenIslandCore")
    app = package / "Sources/OpenIslandApp"
    app.mkdir(parents=True)
    for name in ["HookInstallationCoordinator.swift", "ResourceBundle.swift", "RuntimeAcceptanceConfiguration.swift", "UpdaterFixtureConfiguration.swift", "GitHubUpdateRelease.swift"]:
        shutil.copy2(root / "Sources/OpenIslandApp" / name, app / name)
    shutil.copy2(root / "Sources/OpenIslandApp/Localization/LanguageManager.swift", app / "LanguageManager.swift")
    resources = app / "Resources"
    resources.mkdir()
    for name in ["en.lproj", "zh-Hans.lproj", "zh-Hant.lproj"]:
        shutil.copytree(root / "Sources/OpenIslandApp/Resources" / name, resources / name)
    for name in ["open-island-pi.ts", "open-island-opencode.js"]:
        shutil.copy2(root / "Sources/OpenIslandApp/Resources" / name, resources / name)
    for target, names in {
        "OpenIslandCoreTests": ["AgentIntentStoreTests.swift", "AgentInstallationDetectorTests.swift", "HermesHooksTests.swift", "DesktopConnectionInstallationTests.swift", "HookConfigurationCurrentTests.swift"],
        "OpenIslandAppTests": ["HookInstallationCoordinatorTests.swift", "RuntimeAcceptanceConfigurationTests.swift", "SourceSetupAcceptanceTests.swift"]
    }.items():
        tests = package / "Tests" / target
        tests.mkdir(parents=True)
        for name in names:
            shutil.copy2(root / "Tests" / target / name, tests / name)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "AutoConnectionChecks", defaultLocalization: "en", platforms: [.macOS(.v14)], targets: [
    .target(name: "OpenIslandCore"),
    .target(name: "OpenIslandApp", dependencies: ["OpenIslandCore"], resources: [.process("Resources")]),
    .testTarget(name: "OpenIslandCoreTests", dependencies: ["OpenIslandCore"]),
    .testTarget(name: "OpenIslandAppTests", dependencies: ["OpenIslandApp", "OpenIslandCore"])
])
''')
    command = ["zsh", str(root / "scripts/test-clt.sh"), "--package-path", str(package), "--disable-xctest", "-Xswiftc", "-Xfrontend", "-Xswiftc", "-disable-cross-import-overlays"]
    raise SystemExit(subprocess.run(command, cwd=root, env=environment).returncode)
