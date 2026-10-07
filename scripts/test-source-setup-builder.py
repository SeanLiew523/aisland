#!/usr/bin/env python3
"""Plan/metadata checks only: never compile, sign, install or launch an App."""
import sys
sys.dont_write_bytecode = True
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).with_name('build-v011-acceptance-app.py')
spec = importlib.util.spec_from_file_location('acceptance_builder', path)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

class BuilderTests(unittest.TestCase):
    def test_markers_scope_and_identity(self):
        directory, socket = builder.admission('setup-fixture', '/private/tmp/aisland-v011-acceptance/setup-fixture/bridge.sock', 39)
        common = ('setup-fixture', directory, socket, 39, 'a' * 40)
        ordinary = builder.make_plist(*common)
        self.assertNotIn('AIslandSourceSetupAcceptance', ordinary)
        self.assertTrue(ordinary['AIslandUpdaterFixtureSupported'])
        self.assertTrue(ordinary['OpenIslandDisableUpdates'])
        configured = builder.make_plist(*common, builder.SOURCE_SETUP_AGENTS)
        self.assertTrue(configured['AIslandSourceSetupAcceptance'])
        self.assertEqual(configured['AIslandSourceSetupAgents'], list(builder.SOURCE_SETUP_AGENTS))
        self.assertEqual(configured['AIslandSourceSetupSupportPath'], str(directory / 'support'))
        for agents in [('codex',), ('miniMaxCodeCLI',), ('hermes', 'hermes')]:
            with self.assertRaises(ValueError): builder.make_plist(*common, agents)
    def test_production_paths_and_unmarked_cases_rejected(self):
        with self.assertRaises(ValueError): builder.admission('setup-fixture', '/tmp/open-island-501.sock', 39)
        directory, socket = builder.admission('fresh-zh', '/private/tmp/aisland-v011-acceptance/fresh-zh/bridge.sock', 39)
        with self.assertRaises(ValueError): builder.make_plist('fresh-zh', directory, socket, 39, 'a' * 40, ('hermes',))
        directory, socket = builder.admission('runtime-live', '/private/tmp/aisland-v011-acceptance/runtime-live/bridge.sock', 39)
        self.assertTrue(builder.make_plist('runtime-live', directory, socket, 39, 'a' * 40, ('hermes',))['AIslandSourceSetupAcceptance'])
    def test_approved_r9_frames_old_task_captures_and_r8_score(self):
        hashes = builder.verify_v6_assets()
        self.assertEqual(set(hashes), {'intro-v6.wav', 'native-media.json', 'bloub-r9.json', 'bloub-r9-provenance.json'})

if __name__ == '__main__': unittest.main()
