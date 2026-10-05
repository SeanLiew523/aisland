#!/usr/bin/env python3
"""Run unchanged production MiniMax copy/controller fixtures without app startup."""
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parent.parent
developer = subprocess.check_output(['xcode-select', '-p'], text=True).strip()
frameworks = developer + '/Library/Developer/Frameworks'
with tempfile.TemporaryDirectory(prefix='aisland-minimax-copy-') as directory:
    package = Path(directory)
    shutil.copytree(root / 'Sources/OpenIslandCore', package / 'Sources/OpenIslandCore')
    for folder in ['Sources/OpenIslandApp', 'Tests/OpenIslandAppTests']:
        (package / folder).mkdir(parents=True)
    sources = ['MiniMaxCodeConversationController.swift', 'MiniMaxCodePasteboardSnapshot.swift', 'MiniMaxCodeTopbarSelection.swift', 'MiniMaxCodeWindowSelection.swift']
    tests = ['MiniMaxCodeCopyDiagnosticsTests.swift', 'MiniMaxCodeConversationControllerTests.swift', 'MiniMaxCodePasteboardSnapshotTests.swift', 'MiniMaxCodeTopbarSelectionTests.swift', 'MiniMaxCodeWindowSelectionTests.swift']
    for name in sources:
        shutil.copy2(root / 'Sources/OpenIslandApp' / name, package / 'Sources/OpenIslandApp' / name)
    for name in tests:
        shutil.copy2(root / 'Tests/OpenIslandAppTests' / name, package / 'Tests/OpenIslandAppTests' / name)
    (package / 'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MiniMaxCopyVerification", platforms: [.macOS(.v14)], targets: [
.target(name: "OpenIslandCore"),
.target(name: "OpenIslandApp", dependencies: ["OpenIslandCore"]),
.testTarget(name: "OpenIslandAppTests", dependencies: ["OpenIslandApp", "OpenIslandCore"])
])
''')
    command = ['swift', 'test', '--package-path', str(package), '--enable-swift-testing', '--disable-xctest']
    if (Path(frameworks) / 'Testing.framework').exists():
        command += ['-Xswiftc', '-F', '-Xswiftc', frameworks, '-Xlinker', '-F' + frameworks, '-Xlinker', '-rpath', '-Xlinker', frameworks, '-Xlinker', '-rpath', '-Xlinker', developer + '/Library/Developer/usr/lib', '-Xswiftc', '-Xfrontend', '-Xswiftc', '-disable-cross-import-overlays']
    raise SystemExit(subprocess.run(command).returncode)
