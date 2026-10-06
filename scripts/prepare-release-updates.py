#!/usr/bin/env python3
"""Sign an exact AIsland release archive/feed using its dedicated Keychain key.
Never export a private key, install an app, mutate a repository feed or publish.
"""
import argparse
import base64
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / 'config/packaging/AIslandUpdates.json').read_text())
TOOLS = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'

def run(args):
    return subprocess.check_output([str(x) for x in args], text=True).strip()

def source_snapshot():
    digest = hashlib.sha256()
    digest.update(subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD']))
    for name in sorted(subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).split(b'\0')):
        if not name: continue
        path = ROOT / name.decode()
        stat = path.lstat()
        digest.update(name + b'\0' + str((stat.st_mode, stat.st_size, stat.st_mtime_ns)).encode())
    return digest.hexdigest()

def preflight():
    public = run([TOOLS / 'generate_keys', '--account', CONFIG['keychain_account'], '-p'])
    if public != CONFIG['public_key']:
        raise ValueError('Keychain public key does not match the committed AIsland trust anchor.')
    if len(base64.b64decode(public, validate=True)) != 32:
        raise ValueError('Invalid AIsland Ed25519 public key.')

def prepare(package):
    package = Path(package).resolve()
    if not package.is_relative_to(ROOT / 'output'):
        raise ValueError('Only this repository output can be prepared.')
    app = package / 'AIsland.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    subprocess.run(['python3', str(ROOT / 'scripts/verify-update-configuration.py'), '--app', str(app)], check=True)
    if info.get('CFBundleIdentifier') != 'dev.aisland.app' or any('Acceptance' in k or 'Fixture' in k for k in info):
        raise ValueError('Only a normal AIsland release bundle is permitted.')
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version) or not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Numeric release version and build are required.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = subprocess.run(['codesign', '-dv', '--verbose=2', str(app)], capture_output=True, text=True, check=True).stderr
    if 'Authority=Developer ID Application:' not in signature or 'runtime' not in signature:
        raise ValueError('Developer ID Application and Hardened Runtime are required.')
    archive = package / 'AIsland.zip'
    signed = run([TOOLS / 'sign_update', '--account', CONFIG['keychain_account'], archive])
    attributes = ET.fromstring(f'<enclosure xmlns:sparkle="{NS}" {signed}/>').attrib
    if int(attributes['length']) != archive.stat().st_size:
        raise ValueError('Archive size changed during signing.')
    url = f'https://github.com/SeanLiew523/aisland/releases/download/v{version}/AIsland.zip'
    ET.register_namespace('sparkle', NS)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'AIsland Updates'
    ET.SubElement(channel, 'link').text = 'https://github.com/SeanLiew523/aisland/releases'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'AIsland {version}'
    ET.SubElement(item, f'{{{NS}}}version').text = build
    ET.SubElement(item, f'{{{NS}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = '14.0'
    ET.SubElement(item, 'pubDate').text = datetime.datetime.now(datetime.timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')
    ET.SubElement(item, 'enclosure', dict(attributes, url=url, type='application/octet-stream'))
    feed = package / 'appcast.xml'
    if feed.exists():
        raise ValueError('Existing signed feed is preserved; use a fresh package output.')
    ET.indent(rss)
    feed.write_bytes(ET.tostring(rss, encoding='utf-8', xml_declaration=True) + b'\n')
    run([TOOLS / 'sign_update', '--account', CONFIG['keychain_account'], feed])
    subprocess.run(['swift', str(ROOT / 'scripts/verify-release-updates.swift'), str(package), CONFIG['public_key']], check=True)
    print('Prepared signed appcast.xml and verified exact archive/feed signatures; nothing published.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', nargs='?')
    parser.add_argument('--preflight', action='store_true')
    parser.add_argument('--source-snapshot', action='store_true')
    args = parser.parse_args()
    if args.source_snapshot:
        print(source_snapshot())
        return
    if not args.preflight and not args.package:
        parser.error('Pass a release output directory or --preflight.')
    preflight()
    if args.package:
        prepare(args.package)
    else:
        print('Dedicated AIsland Keychain public identity matches the committed trust anchor.')

if __name__ == '__main__':
    main()
