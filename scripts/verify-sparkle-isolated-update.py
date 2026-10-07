#!/usr/bin/env python3
"""Run an ephemeral, locally signed Sparkle install/relaunch fixture.

Only an app under a newly created /private/tmp/aisland-updater-fixture-* directory
is launched/replaced. No AIsland app, hooks, preferences or signing keys are used.
This proves Sparkle's installer, not GitHub publication or the AIsland Settings UI.
"""
import argparse
import atexit
import http.server
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid

REPO = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run', action='store_true', help='Launch only the isolated fixture app, install and relaunch it.')
parser.add_argument('--tamper-feed', action='store_true', help='Corrupt the signed feed; installation must fail.')
parser.add_argument('--tamper-archive', action='store_true', help='Corrupt the signed archive; installation must fail.')
args = parser.parse_args()
if not args.run:
    print('Plan: ephemeral Ed25519 key in memory, dedicated random bundle ID, loopback signed feed, own v1→v2 app only; assert relaunched v2 receipt. Use --run to execute.')
    raise SystemExit(0)
framework = REPO / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
if not framework.is_dir():
    raise SystemExit('Run swift package resolve first.')
root = Path(tempfile.mkdtemp(prefix='aisland-updater-fixture-', dir='/private/tmp'))
identifier = 'dev.aisland.updater.fixture.' + uuid.uuid4().hex
atexit.register(lambda: shutil.rmtree(root, ignore_errors=True))
receipt = root / 'receipt.json'
app = root / 'installed/Updater Fixture.app'
print(json.dumps({'fixture_root': str(root), 'bundle_id': identifier, 'production_modified': False}), flush=True)

class Server(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(root), **kw)
    def log_message(self, *_):
        pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Server)
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f'http://127.0.0.1:{server.server_port}'

def run(command):
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)

# A small Cocoa host with a visible fixture window. Its custom driver exercises
# the same Sparkle callbacks as UpdateChecker; fixture consent is --run above.
source = root / 'Host.swift'
source.write_text(r'''
import AppKit
import Sparkle
@MainActor final class Host: NSObject, NSApplicationDelegate, SPUUserDriver {
    var updater: SPUUpdater!
    var window: NSWindow!
    var events: [String] = []
    let receipt = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "FixtureReceipt") as! String)
    func record(_ event: String) {
        if events.isEmpty, let data = try? Data(contentsOf: receipt),
           let prior = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let previousEvents = prior["events"] as? [String] { events = previousEvents }
        events.append(event)
        try! JSONSerialization.data(withJSONObject: ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")!, "events": events]).write(to: receipt)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 130), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Isolated Sparkle Update Fixture"
        window.contentView = NSTextField(labelWithString: "Only this temporary fixture will update and restart.")
        window.center(); window.makeKeyAndOrderFront(nil)
        record("launched")
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            record("relaunched-v2"); NSApp.terminate(nil); return
        }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        do { try updater.start(); updater.checkForUpdates() }
        catch { record("failed-start"); NSApp.terminate(nil) }
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(.init(automaticUpdateChecks: false, sendSystemProfile: false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { record("checking") }
    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard item.signingValidationStatus == .succeeded else { record("failed-feed-signature"); reply(.dismiss); NSApp.terminate(nil); return }
        record("signed-feed-accepted"); reply(.install)
    }
    func showUpdateReleaseNotes(with data: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { record("failed-no-update"); acknowledgement(); NSApp.terminate(nil) }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { record("failed-update"); print(error); acknowledgement(); NSApp.terminate(nil) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { record("downloading") }
    func showDownloadDidReceiveExpectedContentLength(_ length: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) { record("download-progress") }
    func showDownloadDidStartExtractingUpdate() { record("extracting") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { record("ready-install"); reply(.install) }
    func showInstallingUpdate(withApplicationTerminated terminated: Bool, retryTerminatingApplication: @escaping () -> Void) { record("installing") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { record("installed"); acknowledgement() }
    func dismissUpdateInstallation() {}
}
MainActor.assumeIsolated {
let application = NSApplication.shared
let host = Host()
application.delegate = host
application.setActivationPolicy(.regular)
application.run()
}
''')
binary = root / 'FixtureHost'
run(['swiftc', '-F', str(framework.parent), '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', '@loader_path/../Frameworks', str(source), '-o', str(binary)])
# The signer keeps its randomly generated private key solely in process memory.
# It builds/signs both fixture apps, then signs their ZIP and feed with that key.
signer = root / 'Signer.swift'
signer.write_text(r'''
import Foundation
import CryptoKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let publicBase = CommandLine.arguments[2]
let identifier = CommandLine.arguments[3]
let framework = CommandLine.arguments[4]
let key = Curve25519.Signing.PrivateKey()
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
func run(_ executable: String, _ arguments: [String]) throws {
    let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
    try p.run(); p.waitUntilExit(); guard p.terminationStatus == 0 else { fatalError("Fixture command failed") }
}
for version in ["1", "2"] {
    let app = root.appendingPathComponent(version == "1" ? "installed/Updater Fixture.app" : "payload/Updater Fixture.app")
    for directory in ["MacOS", "Frameworks"] { try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/" + directory), withIntermediateDirectories: true) }
    try FileManager.default.copyItem(at: root.appendingPathComponent("FixtureHost"), to: app.appendingPathComponent("Contents/MacOS/FixtureHost"))
    try run("/usr/bin/ditto", [framework, app.appendingPathComponent("Contents/Frameworks/Sparkle.framework").path])
    let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleName": "Updater Fixture", "CFBundleExecutable": "FixtureHost", "CFBundlePackageType": "APPL", "CFBundleVersion": version, "CFBundleShortVersionString": "0.0." + version, "NSPrincipalClass": "NSApplication", "LSMinimumSystemVersion": "14.0", "SUPublicEDKey": publicKey, "SUFeedURL": publicBase + "/appcast.xml", "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true, "SUEnableAutomaticChecks": false, "SUAutomaticallyUpdate": false, "FixtureReceipt": root.appendingPathComponent("receipt.json").path, "NSAppTransportSecurity": ["NSAllowsLocalNetworking": true]]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
}
let archive = root.appendingPathComponent("fixture.zip")
try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", root.appendingPathComponent("payload/Updater Fixture.app").path, archive.path])
let bytes = try Data(contentsOf: archive)
let signature = try key.signature(for: bytes).base64EncodedString()
let feed = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Isolated fixture</title><item><title>v2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString><enclosure url="\(publicBase)/fixture.zip" length="\(bytes.count)" type="application/octet-stream" sparkle:edSignature="\(signature)"/></item></channel></rss>

"""
let feedData = Data(feed.utf8)
let signed = feed + "<!-- sparkle-signatures:\nedSignature: \(try key.signature(for: feedData).base64EncodedString())\nlength: \(feedData.count)\n-->\n"
try Data(signed.utf8).write(to: root.appendingPathComponent("appcast.xml"))
''')
run(['swift', str(signer), str(root), url, identifier, str(framework)])
if args.tamper_feed:
    feed = root / 'appcast.xml'
    feed.write_bytes(feed.read_bytes().replace(b'Isolated fixture', b'Tampered fixture'))
if args.tamper_archive:
    with (root / 'fixture.zip').open('ab') as archive:
        archive.write(b'tampered-fixture')
try:
    run(['open', '-n', str(app)])
    deadline = time.monotonic() + 60
    result = None
    while time.monotonic() < deadline:
        if receipt.exists():
            try:
                observed = json.loads(receipt.read_text())
                if 'relaunched-v2' in observed['events'] or any(e.startswith('failed') for e in observed['events']):
                    result = observed
                    break
            except (ValueError, OSError):
                pass
        time.sleep(.2)
    assert result, 'Fixture did not finish within 60 seconds; inspect isolated logs.'
    actual = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleVersion']
    if args.tamper_feed:
        assert result['version'] == actual == '1' and any(e.startswith('failed') for e in result['events']), result
    elif args.tamper_archive:
        assert result['version'] == actual == '1' and 'failed-update' in result['events'], result
    else:
        assert result['version'] == actual == '2' and 'relaunched-v2' in result['events'], result
        assert all(e in result['events'] for e in ['signed-feed-accepted', 'download-progress', 'extracting', 'ready-install', 'installing']), result
        run(['codesign', '--verify', '--deep', '--strict', str(app)])
    print(json.dumps({'result': result, 'installed_bundle_version': actual, 'tamper_rejected': args.tamper_archive or args.tamper_feed, 'production_modified': False}))
finally:
    server.shutdown()
    # Only the random dedicated fixture ID can be terminated/removed.
    subprocess.run(['pkill', '-f', '^' + str(app / 'Contents/MacOS/FixtureHost')], check=False)
    subprocess.run(['defaults', 'delete', identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    shutil.rmtree(root)
