#!/usr/bin/env python3
"""Run unchanged updater source/tests in isolation from unrelated app tests."""
from pathlib import Path
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent
developer = subprocess.check_output(['xcode-select', '-p'], text=True).strip()
frameworks = developer + '/Library/Developer/Frameworks'
sparkle = root / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework'
assert sparkle.exists(), 'Run swift package resolve first.'
with tempfile.TemporaryDirectory(prefix='aisland-update-tests-') as directory:
    package = Path(directory)
    (package / 'Sources/OpenIslandApp').mkdir(parents=True)
    (package / 'Tests/OpenIslandAppTests').mkdir(parents=True)
    for name in ['UpdateChecker.swift', 'GitHubUpdateRelease.swift']:
        shutil.copy2(root / 'Sources/OpenIslandApp' / name, package / 'Sources/OpenIslandApp' / name)
    shutil.copy2(root / 'Tests/OpenIslandAppTests/GitHubUpdateTests.swift', package / 'Tests/OpenIslandAppTests')
    (package / 'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "UpdaterVerification", platforms: [.macOS(.v14)], targets: [
    .binaryTarget(name: "Sparkle", path: "Sparkle.xcframework"),
    .target(name: "OpenIslandApp", dependencies: ["Sparkle"]),
    .testTarget(name: "OpenIslandAppTests", dependencies: ["OpenIslandApp", "Sparkle"])
])
''')
    shutil.copytree(sparkle, package / 'Sparkle.xcframework', symlinks=True)
    command = ['swift', 'test', '--package-path', str(package), '--enable-swift-testing']
    if (Path(frameworks) / 'Testing.framework').exists():
        command += ['-Xswiftc', '-F', '-Xswiftc', frameworks,
                    '-Xlinker', '-F' + frameworks, '-Xlinker', '-rpath', '-Xlinker', frameworks,
                    '-Xlinker', '-rpath', '-Xlinker', developer + '/Library/Developer/usr/lib',
                    '-Xswiftc', '-Xfrontend', '-Xswiftc', '-disable-cross-import-overlays']
    raise SystemExit(subprocess.run(command, cwd=root).returncode)
