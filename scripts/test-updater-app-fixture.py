#!/usr/bin/env python3
"""Verify script admission and exact loopback serving, without launching apps."""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request
import uuid

script=Path(__file__).with_name('prepare-updater-app-fixture.py')
spec=importlib.util.spec_from_file_location('updater_fixture',script)
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class FixtureScriptTests(unittest.TestCase):
    def setUp(self):
        token=uuid.uuid4().hex
        self.root=Path('/private/tmp')/(module.PREFIX+token)
        app=self.root/'installed/AIsland.app/Contents'; app.mkdir(parents=True)
        self.identifier=module.BUNDLE_PREFIX+token[-16:]
        self.manifest={'root':str(self.root),'bundle_id':self.identifier,'origin':'http://127.0.0.1:51234',
                       'public_key':'fixture-public-only','runtime_case':'upd-'+token[-16:]}
        self.info={'AIslandUpdaterFixture':True,'AIslandUpdaterFixtureSupported':True,'OpenIslandRuntimeAcceptance':True,
                   'AIslandUpdaterFixtureRoot':str(self.root),'AIslandUpdaterFixtureOrigin':self.manifest['origin'],
                   'CFBundleIdentifier':self.identifier,'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True,
                   'SUPublicEDKey':self.manifest['public_key'],'OpenIslandDisableUpdates':False}
        self.write()
    def tearDown(self): shutil.rmtree(self.root)
    def write(self):
        (self.root/'fixture.json').write_text(json.dumps(self.manifest))
        (self.root/'installed/AIsland.app/Contents/Info.plist').write_bytes(plistlib.dumps(self.info))
    def testCanonicalRootAndDomainCannotTargetProduction(self):
        module.load(self.root)
        for root in ['/Applications/AIsland.app','/private/tmp/aisland-updater-app-fixture-unsafe','/tmp/'+self.root.name]:
            with self.assertRaises(ValueError): module.admit_root(root)
        self.manifest['bundle_id']='dev.aisland.app'; self.write()
        with self.assertRaises(ValueError): module.load(self.root)
    def testManifestCannotRedirectCleanupToAnotherCase(self):
        self.manifest['runtime_case']='../'; self.write()
        with self.assertRaises(ValueError): module.load(self.root)
    def testSourceSetupAndWeakTrustRemainRejected(self):
        for key,value in [('SURequireSignedFeed',False),('SUVerifyUpdateBeforeExtraction',False),('AIslandSourceSetupAcceptance',True)]:
            original=self.info.copy(); self.info[key]=value; self.write()
            with self.assertRaises(ValueError): module.load(self.root)
            self.info=original
    def testLoopbackServerExposesOnlyThreeExactPublicAssets(self):
        public=self.root/'public'; public.mkdir()
        assets=public/'SeanLiew523/aisland/releases/download/v0.1.2'; assets.mkdir(parents=True)
        (public/'latest.json').write_text('{}')
        (assets/'appcast.xml').write_text('signed-feed-fixture')
        (assets/'AIsland.zip').write_bytes(b'zip-fixture-bytes')
        (self.root/'private.txt').write_text('must-never-be-served')
        server=module.http.server.ThreadingHTTPServer(('127.0.0.1',0),module.Handler)
        server.root=self.root; server.rate_kib=4096
        thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        origin=f'http://127.0.0.1:{server.server_port}'
        try:
            with urllib.request.urlopen(origin+'/latest.json') as response: self.assertEqual(response.read(),b'{}')
            request=urllib.request.Request(origin+'/SeanLiew523/aisland/releases/download/v0.1.2/AIsland.zip',method='HEAD')
            with urllib.request.urlopen(request) as response: self.assertEqual(int(response.headers['Content-Length']),17)
            for path in ['/private.txt','/../private.txt','/latest.json?redirect=1','/payload/AIsland.app/Contents/Info.plist']:
                with self.assertRaises(urllib.error.HTTPError) as error: urllib.request.urlopen(origin+path)
                self.assertEqual(error.exception.code,404); error.exception.close()
        finally: server.shutdown(); server.server_close(); thread.join()
    def testCleanupRefusesProcessQueryErrorsBeforeAnyMutation(self):
        for code in [2,3,-9]:
            with self.subTest(returncode=code), patch('sys.argv',['fixture','--cleanup',str(self.root)]), \
                 patch.object(module.subprocess,'run',return_value=subprocess.CompletedProcess([],code)) as query, \
                 patch.object(module.shutil,'rmtree') as remove:
                with self.assertRaisesRegex(ValueError,'process check failed.*cleanup refused'):
                    module.main()
                query.assert_called_once()
                self.assertEqual(query.call_args.args[0][:2],['pgrep','-f'])
                remove.assert_not_called()
                self.assertTrue(self.root.exists())
    def testCleanupRefusesMatchingLiveFixtureBeforeAnyMutation(self):
        with patch('sys.argv',['fixture','--cleanup',str(self.root)]), \
             patch.object(module.subprocess,'run',return_value=subprocess.CompletedProcess([],0)) as query, \
             patch.object(module.shutil,'rmtree') as remove:
            with self.assertRaisesRegex(ValueError,'Quit this fixture app'):
                module.main()
            query.assert_called_once(); remove.assert_not_called()
    def testCleanupContinuesOnlyAfterConfirmedNoMatch(self):
        with patch('sys.argv',['fixture','--cleanup',str(self.root)]), \
             patch.object(module.subprocess,'run',return_value=subprocess.CompletedProcess([],1)) as query, \
             patch.object(module.shutil,'rmtree') as remove, contextlib.redirect_stdout(io.StringIO()):
            module.main()
            self.assertEqual(query.call_count,2)
            self.assertEqual(query.call_args_list[1].args[0],['defaults','delete',self.identifier])
            self.assertEqual(remove.call_count,2)
            self.assertEqual(remove.call_args_list[0].args[0],Path('/private/tmp/aisland-v011-acceptance')/self.manifest['runtime_case'])
            self.assertEqual(remove.call_args_list[1].args[0],self.root)
    def testCleanupPatternCompilesOnActualMacOSPgrep(self):
        app=self.root/'installed/AIsland.app'
        pattern='^'+module.re.escape(str(app/'Contents/MacOS/OpenIslandApp'))+'( |$)'
        result=subprocess.run(['pgrep','-f',pattern],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
        self.assertEqual(result.returncode,1,result.stderr)
    def testSignerSwiftTypeChecksWithoutPreparingOrLaunchingApps(self):
        with tempfile.TemporaryDirectory(prefix='aisland-updater-signer-check-') as tmp:
            swift=Path(tmp)/'Signer.swift'; swift.write_text(module.SIGNER)
            subprocess.run(['swiftc','-typecheck',str(swift)],check=True)

if __name__=='__main__': unittest.main()
