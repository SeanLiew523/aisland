#!/usr/bin/env python3
"""Prepare/serve signed updates for a complete, explicitly isolated AIsland app.
Never launches an app, builds the product, creates credentials, or publishes.
The signing key is generated only in a short-lived CryptoKit process's memory.
"""
import argparse
import hashlib
import http.server
import json
from pathlib import Path
import plistlib
import re
import shutil
import socket
import subprocess
import tempfile
import time
import uuid

PREFIX = 'aisland-updater-app-fixture-'
BUNDLE_PREFIX = 'dev.aisland.v011.acceptance.upd-'

def run(command, capture=False):
    return subprocess.run(command, check=True, stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                          stderr=subprocess.PIPE if capture else None, text=capture).stdout

def admit_root(value):
    root = Path(value)
    if not root.is_absolute() or root.parent != Path('/private/tmp') or not re.fullmatch(PREFIX + '[0-9a-f]{32}', root.name) or root.resolve() != root:
        raise ValueError('Only a canonical, random fixture root under /private/tmp is permitted.')
    return root

def load(root):
    root = admit_root(root)
    manifest = json.loads((root / 'fixture.json').read_text())
    token = root.name[len(PREFIX):]
    identifier = BUNDLE_PREFIX + token[-16:]
    if manifest['root'] != str(root) or manifest['bundle_id'] != identifier or manifest.get('runtime_case') != 'upd-' + token[-16:] or not re.fullmatch(r'http://127\.0\.0\.1:[0-9]+', manifest['origin']):
        raise ValueError('Fixture manifest mismatch.')
    port = int(manifest['origin'].rsplit(':', 1)[1])
    if not 1024 <= port <= 65535:
        raise ValueError('Unsafe fixture port.')
    app = root / 'installed/AIsland.app'
    if app.resolve() != app:
        raise ValueError('Fixture app was redirected.')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    expected = {'AIslandUpdaterFixture': True, 'AIslandUpdaterFixtureSupported': True, 'OpenIslandRuntimeAcceptance': True,
                'AIslandUpdaterFixtureRoot': str(root), 'AIslandUpdaterFixtureOrigin': manifest['origin'],
                'CFBundleIdentifier': identifier, 'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
                'SUPublicEDKey': manifest['public_key'], 'OpenIslandDisableUpdates': False}
    if any(info.get(k) != v for k, v in expected.items()) or any(k.startswith('AIslandSourceSetup') for k in info):
        raise ValueError('Installed fixture metadata/trust mismatch.')
    return root, manifest, app, info

SIGNER = r'''
import Foundation
import CryptoKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CommandLine.arguments[2]
let origin = CommandLine.arguments[3]
let identifier = CommandLine.arguments[4]
let currentBuild = Int(CommandLine.arguments[5])!
let key = Curve25519.Signing.PrivateKey()
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
func run(_ exe: String, _ arguments: [String]) throws {
    let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = arguments
    try p.run(); p.waitUntilExit(); guard p.terminationStatus == 0 else { fatalError("Fixture preparation failed") }
}
for (offset, version) in ["0.1.1", "0.1.2"].enumerated() {
    let app = root.appendingPathComponent(offset == 0 ? "installed/AIsland.app" : "payload/AIsland.app")
    try FileManager.default.createDirectory(at: app.deletingLastPathComponent(), withIntermediateDirectories: true)
    try run("/usr/bin/ditto", [source, app.path])
    let plist = app.appendingPathComponent("Contents/Info.plist")
    var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
    // A reused full-app template may have source-setup admission. Only its
    // binary/resources are reused; that independent opt-in is never copied.
    for key in Array(info.keys) where key.hasPrefix("AIslandSourceSetup") { info.removeValue(forKey: key) }
    info["CFBundleIdentifier"] = identifier
    info["CFBundleName"] = "AIsland Update Acceptance"
    info["CFBundleDisplayName"] = "AIsland Update Acceptance"
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = String(currentBuild + offset)
    info["AIslandUpdaterFixture"] = true
    info["AIslandUpdaterFixtureRoot"] = root.path
    info["AIslandUpdaterFixtureOrigin"] = origin
    info["OpenIslandDisableUpdates"] = false
    info["AIslandUpdateSigningIdentity"] = "aisland-ed25519-v1"
    info["SUPublicEDKey"] = publicKey
    info["SURequireSignedFeed"] = true
    info["SUVerifyUpdateBeforeExtraction"] = true
    info["SUEnableAutomaticChecks"] = false
    info["SUAutomaticallyUpdate"] = false
    info["SUFeedURL"] = origin + "/SeanLiew523/aisland/releases/download/v0.1.2/appcast.xml"
    info["NSAppTransportSecurity"] = ["NSAllowsLocalNetworking": true]
    let caseName = String(identifier.dropFirst("dev.aisland.v011.acceptance.".count))
    let runtime = "/private/tmp/aisland-v011-acceptance/" + caseName
    info["OpenIslandAcceptanceSocketPath"] = runtime + "/bridge.sock"
    info["OpenIslandAcceptanceRegistryPath"] = runtime + "/runtime-lifecycle.json"
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
    try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
}
let assets = root.appendingPathComponent("public/SeanLiew523/aisland/releases/download/v0.1.2")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
let archive = assets.appendingPathComponent("AIsland.zip")
try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", root.appendingPathComponent("payload/AIsland.app").path, archive.path])
let archiveData = try Data(contentsOf: archive)
let archiveSignature = try key.signature(for: archiveData).base64EncodedString()
let feed = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>AIsland full-app isolated fixture</title><item><title>Fixture 0.1.2</title><sparkle:version>\(currentBuild + 1)</sparkle:version><sparkle:shortVersionString>0.1.2</sparkle:shortVersionString><enclosure url="\(origin)/SeanLiew523/aisland/releases/download/v0.1.2/AIsland.zip" length="\(archiveData.count)" type="application/octet-stream" sparkle:edSignature="\(archiveSignature)"/></item></channel></rss>

"""
let feedData = Data(feed.utf8)
let signedFeed = feed + "<!-- sparkle-signatures:\nedSignature: \(try key.signature(for: feedData).base64EncodedString())\nlength: \(feedData.count)\n-->\n"
try Data(signedFeed.utf8).write(to: assets.appendingPathComponent("appcast.xml"))
let metadata: [String: Any] = ["tag_name": "v0.1.2", "draft": false, "prerelease": false,
    "html_url": "https://github.com/SeanLiew523/aisland/releases/tag/v0.1.2",
    "assets": ["appcast.xml", "AIsland.zip"].map { name in ["name": name, "size": name == "AIsland.zip" ? archiveData.count : signedFeed.utf8.count,
        "state": "uploaded", "browser_download_url": origin + "/SeanLiew523/aisland/releases/download/v0.1.2/" + name] as [String: Any] }]
try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]).write(to: root.appendingPathComponent("public/latest.json"))
try Data(publicKey.utf8).write(to: root.appendingPathComponent("public-key.txt"))
'''

def prepare(template, tamper):
    template = Path(template).absolute()
    if template.resolve() != template or template.suffix != '.app':
        raise ValueError('Template must be a canonical full acceptance app.')
    info = plistlib.loads((template / 'Contents/Info.plist').read_bytes())
    if info.get('OpenIslandRuntimeAcceptance') is not True or info.get('AIslandUpdaterFixtureSupported') is not True or not info.get('CFBundleIdentifier', '').startswith('dev.aisland.v011.acceptance.') or info.get('CFBundleShortVersionString') != '0.1.1' or info.get('AIslandUpdaterFixture') is not None:
        raise ValueError('Build a fresh full acceptance app with the validated fixture interface first.')
    if not (template / 'Contents/Frameworks/Sparkle.framework').is_dir() or not (template / 'Contents/Resources/OpenIsland_OpenIslandApp.bundle').is_dir():
        raise ValueError('Template is missing real Sparkle or full application resources.')
    run(['codesign', '--verify', '--deep', '--strict', str(template)])
    source_binary = template / 'Contents/MacOS/OpenIslandApp'
    original = hashlib.sha256(source_binary.read_bytes()).hexdigest()
    token = uuid.uuid4().hex
    root = Path('/private/tmp') / (PREFIX + token)
    root.mkdir(mode=0o700)
    identifier = BUNDLE_PREFIX + token[-16:]
    reservation = socket.socket(); reservation.bind(('127.0.0.1', 0))
    port = reservation.getsockname()[1]
    origin = f'http://127.0.0.1:{port}'
    try:
        signer = root / 'Signer.swift'; signer.write_text(SIGNER)
        run(['swift', str(signer), str(root), str(template), origin, identifier, str(int(info['CFBundleVersion']))])
        signer.unlink() # No private key was ever written; signer has now exited.
        asset = root / 'public/SeanLiew523/aisland/releases/download/v0.1.2'
        if tamper == 'feed':
            feed = asset / 'appcast.xml'; feed.write_bytes(feed.read_bytes().replace(b'AIsland full-app isolated fixture', b'Altered full-app isolated fixture'))
        elif tamper == 'archive':
            with (asset / 'AIsland.zip').open('ab') as archive: archive.write(b'invalid-tamper')
        manifest = {'root': str(root), 'bundle_id': identifier, 'origin': origin, 'template': str(template),
            'source_commit': info.get('AIslandSourceCommit'), 'template_binary_sha256': original,
            'current_version': '0.1.1', 'next_version': '0.1.2', 'current_build': str(info['CFBundleVersion']),
            'next_build': str(int(info['CFBundleVersion']) + 1), 'public_key': (root / 'public-key.txt').read_text(),
            'tamper': tamper, 'production_modified': False, 'apps_launched': False,
            'runtime_case': 'upd-' + token[-16:]}
        (root / 'public-key.txt').unlink()
        (root / 'fixture.json').write_text(json.dumps(manifest, indent=2)+'\n')
        assert hashlib.sha256(source_binary.read_bytes()).hexdigest() == original
        load(root)
        print(json.dumps(manifest, indent=2))
        print('Serve:', 'python3 scripts/prepare-updater-app-fixture.py --serve', root)
        print('Root GUI operator may open only:', root / 'installed/AIsland.app')
        print('Complete mandatory welcome naturally before testing Settings. This script has not launched the app.')
    except BaseException:
        shutil.rmtree(root); raise
    finally:
        reservation.close()

class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self): self.deliver(head=True)
    def do_GET(self): self.deliver(head=False)
    def log_message(self, *_): pass
    def deliver(self, head):
        allowed = ['/latest.json', '/SeanLiew523/aisland/releases/download/v0.1.2/appcast.xml', '/SeanLiew523/aisland/releases/download/v0.1.2/AIsland.zip']
        if self.path not in allowed:
            self.send_error(404); return
        path = self.server.root / 'public' / self.path.lstrip('/')
        self.send_response(200); self.send_header('Content-Length', str(path.stat().st_size))
        self.send_header('Content-Type', 'application/json' if self.path.endswith('json') else 'application/octet-stream')
        self.end_headers()
        if head: return
        try:
            with path.open('rb') as data:
                while chunk := data.read(65536):
                    self.wfile.write(chunk); self.wfile.flush()
                    if path.suffix == '.zip': time.sleep(len(chunk)/(self.server.rate_kib*1024))
        except (BrokenPipeError, ConnectionResetError): pass

def inspect(root, expected):
    root, m, app, info = load(root)
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    receipts=[]
    if (root/'updater-events.jsonl').exists():
        receipts=[json.loads(line) for line in (root/'updater-events.jsonl').read_text().splitlines() if line]
    progress=[x for x in receipts if x['event']=='download-progress' and 0 < x.get('bytes',0) < x.get('expected',0)]
    launches=[x for x in receipts if x['event']=='launched']
    phases=[x.get('phase') for x in receipts if x['event']=='phase']
    updated=(info['CFBundleShortVersionString']==m['next_version'] and info['CFBundleVersion']==m['next_build']
        and any(x.get('version')=='0.1.1' for x in launches) and any(x.get('version')=='0.1.2' for x in launches)
        and len({x['pid'] for x in launches})>=2 and bool(progress) and 'installing' in phases)
    rejected=(info['CFBundleShortVersionString']=='0.1.1' and any(p in ['blocked','failed'] for p in phases)
        and not any(x.get('version')=='0.1.2' for x in launches))
    if expected=='updated' and not updated: raise ValueError('No verified full-app update + new-process receipt yet.')
    if expected=='rejected' and not rejected: raise ValueError('No verified rejection receipt yet.')
    print(json.dumps({'updated': updated,'rejected': rejected,'installed_version': info['CFBundleShortVersionString'],
        'installed_build': info['CFBundleVersion'],'launch_receipts': launches,'partial_download_receipts':len(progress),
        'phases':phases,'native_UI_acceptance':'requires root GUI screenshots; receipts alone do not verify visible/reopened Settings',
        'production_modified':False},indent=2))

def main():
    p=argparse.ArgumentParser(description=__doc__); g=p.add_mutually_exclusive_group()
    g.add_argument('--prepare',metavar='FULL_ACCEPTANCE_APP'); g.add_argument('--serve',metavar='FIXTURE_ROOT')
    g.add_argument('--inspect',metavar='FIXTURE_ROOT'); g.add_argument('--cleanup',metavar='FIXTURE_ROOT')
    p.add_argument('--tamper',choices=['feed','archive']); p.add_argument('--rate-kib',type=int,default=512)
    p.add_argument('--expect',choices=['updated','rejected']); a=p.parse_args()
    if a.prepare: prepare(a.prepare,a.tamper)
    elif a.serve:
        root,m,_,_=load(a.serve)
        if not 64<=a.rate_kib<=4096: raise ValueError('Rate must be 64–4096 KiB/s.')
        server=http.server.ThreadingHTTPServer(('127.0.0.1',int(m['origin'].rsplit(':',1)[1])),Handler)
        server.root=root; server.rate_kib=a.rate_kib
        print('READY '+m['origin']+'; no app launched',flush=True)
        try: server.serve_forever()
        except KeyboardInterrupt: pass
        finally: server.server_close()
    elif a.inspect: inspect(a.inspect,a.expect)
    elif a.cleanup:
        root,m,app,_=load(a.cleanup)
        running=subprocess.run(['pgrep','-f','^'+re.escape(str(app/'Contents/MacOS/OpenIslandApp'))+'(?: |$)'],stdout=subprocess.DEVNULL).returncode==0
        if running: raise ValueError('Quit this fixture app before cleanup; this script never terminates another app.')
        subprocess.run(['defaults','delete',m['bundle_id']],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        runtime=Path('/private/tmp/aisland-v011-acceptance')/m['runtime_case']
        if runtime.resolve()!=runtime: raise ValueError('Runtime tree redirected; cleanup refused.')
        shutil.rmtree(runtime,ignore_errors=True); shutil.rmtree(root)
        print('Removed only the random fixture, its preferences and dedicated runtime case.')
    else: print('Plan only. --prepare <fresh full acceptance.app>, then --serve <printed root>; GUI is performed separately by the root operator. --inspect/--expect only assess local receipts. No public publication or production trust changes.')

if __name__=='__main__':
    try: main()
    except (ValueError,OSError,subprocess.CalledProcessError) as error: raise SystemExit(str(error))
