#!/usr/bin/env python3
"""Actual public-key verification and corrupted archive/feed rejection.
Only temporary synthetic files and an in-memory ephemeral key are used.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parent.parent
SIGNER=r"""
import Foundation
import CryptoKit
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let key=Curve25519.Signing.PrivateKey()
let archive=Data("temporary original archive fixture".utf8)
try archive.write(to:root.appendingPathComponent("AIsland.zip"))
let signature=try key.signature(for:archive).base64EncodedString()
let xml="<?xml version=\"1.0\"?><rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><title>Original feed</title><item><enclosure sparkle:edSignature=\"\(signature)\" length=\"\(archive.count)\"/></item></channel></rss>\n"
let bytes=Data(xml.utf8)
let signed=xml+"<!-- sparkle-signatures:\nedSignature: \(try key.signature(for:bytes).base64EncodedString())\nlength: \(bytes.count)\n-->\n"
try Data(signed.utf8).write(to:root.appendingPathComponent("appcast.xml"))
try Data(key.publicKey.rawRepresentation.base64EncodedString().utf8).write(to:root.appendingPathComponent("public.txt"))
"""
class Signatures(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='aisland-release-signature-tests-')
        cls.root=Path(cls.temp.name)
        signer=cls.root/'Signer.swift'; signer.write_text(SIGNER)
        subprocess.run(['swift',str(signer),str(cls.root)],check=True)
        cls.verifier=cls.root/'verify'
        subprocess.run(['swiftc',str(ROOT/'scripts/verify-release-updates.swift'),'-o',str(cls.verifier)],check=True)
        cls.key=(cls.root/'public.txt').read_text()
    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()
    def case(self,feed_change=None,archive_change=None,key=None):
        with tempfile.TemporaryDirectory(dir=self.root) as tmp:
            path=Path(tmp)
            for name in ['appcast.xml','AIsland.zip']: shutil.copy2(self.root/name,path/name)
            if feed_change:
                f=path/'appcast.xml'; f.write_bytes(feed_change(f.read_bytes()))
            if archive_change:
                f=path/'AIsland.zip'; f.write_bytes(archive_change(f.read_bytes()))
            return subprocess.run([str(self.verifier),str(path),key or self.key],capture_output=True).returncode
    def test_original_signed_archive_and_feed_pass(self): self.assertEqual(self.case(),0)
    def test_changed_feed_title_rejected(self): self.assertNotEqual(self.case(feed_change=lambda b:b.replace(b'Original feed',b'Altered feed')),0)
    def test_changed_archive_rejected(self): self.assertNotEqual(self.case(archive_change=lambda b:b+b'altered'),0)
    def test_wrong_public_key_rejected(self): self.assertNotEqual(self.case(key='AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='),0)
    def test_unsigned_trailing_xml_rejected(self): self.assertNotEqual(self.case(feed_change=lambda b:b+b'<item>unsigned</item>'),0)
    def test_duplicate_signature_comment_rejected(self):
        self.assertNotEqual(self.case(feed_change=lambda b:b+b[b.index(b'<!-- sparkle-signatures:'):]),0)
if __name__=='__main__': unittest.main()
