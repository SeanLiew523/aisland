#!/usr/bin/env python3
"""Parameter/provenance checks; no compiler, real bundle, signing or UI run."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().with_name("build-aisland-app.sh")


class BuilderChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aisland-builder-check-")
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(SCRIPT, self.root / "scripts/build-aisland-app.sh")
        (self.root / ".gitignore").write_text("/output/\n/.build/\n/stubs/\n")
        (self.root / "source.txt").write_text("original")
        for args in [("init", "-q"), ("add", "."), ("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")]:
            subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)
        self.env = dict(os.environ)
        for key in ["OPEN_ISLAND_VERSION", "OPEN_ISLAND_BUILD_NUMBER", "OPEN_ISLAND_SIGN_IDENTITY"]:
            self.env.pop(key, None)

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, *args, validate=True):
        return subprocess.run(["zsh", str(self.root / "scripts/build-aisland-app.sh"), *args,
                               *(["--validate-only"] if validate else [])], cwd=self.root,
                              env=self.env, text=True, capture_output=True)

    def test_explicit_version_build_output_and_clean_commit(self):
        result = self.run_script("--version", "0.1.1", "--build-number", "47", "--output", "output/b47/AIsland.app")
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual((plan["version"], plan["build_number"]), ("0.1.1", "47"))
        self.assertEqual(plan["bundle_identifier"], "dev.aisland.app")
        self.assertEqual(plan["runtime_mode"], "normal")
        self.assertEqual(plan["localizations"], ["en", "zh-Hans", "zh-Hant"])
        self.assertEqual(plan["source_commit"], subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root, text=True).strip())
        self.assertFalse((self.root / "output").exists())

    def test_defaults_and_existing_install_switch_remain_supported(self):
        plan = json.loads(self.run_script("--install").stdout)
        self.assertEqual(plan["version"], "0.1.1")
        self.assertEqual(plan["build_number"], "1")  # This fixture has one commit.
        self.env.update(OPEN_ISLAND_VERSION="0.1.2", OPEN_ISLAND_BUILD_NUMBER="49")
        plan = json.loads(self.run_script().stdout)
        self.assertEqual((plan["version"], plan["build_number"]), ("0.1.2", "49"))
        plan = json.loads(self.run_script("--version", "0.1.1", "--build-number", "47").stdout)
        self.assertEqual((plan["version"], plan["build_number"]), ("0.1.1", "47"))

    def test_bad_parameters_fail_without_building(self):
        for args in [("--version", "0.1"), ("--version", "0.1.1;echo bad"), ("--build-number", "0"),
                     ("--build-number", "-47"), ("--build-number", "47.1"), ("--output", "/Applications/AIsland.app"),
                     ("--output", "output/../AIsland.app"), ("--output", "output/not-an-app"),
                     ("--version",), ("--unknown",)]:
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "output").exists())

    def test_existing_output_and_symlink_escape_are_preserved(self):
        target = self.root / "output/aisland/AIsland.app"
        target.mkdir(parents=True)
        marker = target / "do-not-touch"
        marker.write_text("existing")
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual(marker.read_text(), "existing")
        shutil.rmtree(self.root / "output")
        (self.root / "output").symlink_to(self.root / "outside", target_is_directory=True)
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse((self.root / "outside").exists())

    def test_dirty_source_is_rejected(self):
        (self.root / "source.txt").write_text("modified")
        self.assertNotEqual(self.run_script().returncode, 0)
        (self.root / "source.txt").write_text("original")
        (self.root / "new-source.swift").write_text("untracked")
        self.assertNotEqual(self.run_script().returncode, 0)

    def test_source_change_and_reverted_change_during_mock_build_cannot_publish(self):
        stubs = self.root / "stubs"
        stubs.mkdir()
        security = stubs / "security"
        security.write_text('#!/bin/sh\necho \'1) FAKE "Open Island Dev Local"\'\n')
        security.chmod(0o755)
        swift = stubs / "swift"
        # The fake compiler mutates a fixture input; no source App is built.
        swift.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
if "--show-bin-path" in sys.argv:
    print(pathlib.Path.cwd() / ".build")
else:
    p=pathlib.Path("source.txt")
    p.write_text("changed during mock compile")
    if os.environ.get("RESTORE_FIXTURE_INPUT") == "1": p.write_text("original")
''')
        swift.chmod(0o755)
        self.env["PATH"] = str(stubs) + os.pathsep + self.env["PATH"]
        for restore in [False, True]:
            (self.root / "source.txt").write_text("original")
            self.env["RESTORE_FIXTURE_INPUT"] = "1" if restore else "0"
            result = self.run_script("--version", "0.1.1", "--build-number", "47", validate=False)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("Source", result.stderr)
            self.assertFalse((self.root / "output/aisland/AIsland.app").exists())
            self.assertFalse(list((self.root / "output").rglob("Info.plist")))

    def test_generated_plist_is_normal_and_has_exact_version_provenance(self):
        # Exercise the actual embedded plist generator without assembling an App.
        program = SCRIPT.read_text().split("<<'PY_PLIST'\n", 1)[1].split("\nPY_PLIST", 1)[0]
        plan = json.loads(self.run_script("--version", "0.1.1", "--build-number", "47").stdout)
        info_path = self.root / "fixture.plist"
        subprocess.run(["python3", "-c", program, str(info_path), json.dumps(plan)], check=True)
        info = plistlib.loads(info_path.read_bytes())
        self.assertEqual((info["CFBundleShortVersionString"], info["CFBundleVersion"]), ("0.1.1", "47"))
        self.assertEqual(info["AIslandSourceCommit"], plan["source_commit"])
        self.assertEqual(info["CFBundleLocalizations"], plan["localizations"])
        self.assertNotIn("OpenIslandRuntimeAcceptance", info)
        self.assertFalse(any(k.startswith("AIslandSourceSetup") or k.startswith("AIslandUpdaterFixture") for k in info))

    @unittest.skipUnless(sys.platform == "darwin", "Darwin exclusive publication API")
    def test_exclusive_publish_preserves_even_an_empty_existing_destination(self):
        program = SCRIPT.read_text().split("<<'PY_PUBLISH'\n", 1)[1].split("\nPY_PUBLISH", 1)[0]
        # Plain fixture directories, not an application or compiled bundle.
        source = self.root / "staging"
        destination = self.root / "existing"
        source.mkdir(); destination.mkdir()
        (source / "marker").write_text("own artifact")
        command = ["python3", "-c", program, str(source), str(destination)]
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.assertEqual(list(destination.iterdir()), [])
        self.assertEqual((source / "marker").read_text(), "own artifact")
        destination.rmdir()
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.assertFalse(source.exists())
        self.assertEqual((destination / "marker").read_text(), "own artifact")


if __name__ == "__main__":
    unittest.main(verbosity=2)
