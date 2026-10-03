import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("notarize_artifact", Path(__file__).parents[1] / "notarize-artifact.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NotarizationResultTests(unittest.TestCase):
    def submit_result(self, status, submission_id="submission-id"):
        return subprocess.CompletedProcess([], 0, json.dumps({"id": submission_id, "status": status}), "")

    def run_attempt(self, responses):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        artifact = Path(directory.name) / "AIsland.zip"
        artifact.touch()
        target = Path(directory.name) / "AIsland.app"
        target.mkdir()
        return artifact, target, patch.object(module.subprocess, "run", side_effect=responses)

    def test_invalid_result_with_zero_exit_does_not_staple(self):
        artifact, target, runner = self.run_attempt([
            self.submit_result("Invalid"), subprocess.CompletedProcess([], 0),
        ])
        with runner as mocked:
            with self.assertRaisesRegex(RuntimeError, "not accepted"):
                module.notarize(artifact, target, "test-profile")
            self.assertFalse(any("stapler" in call.args[0] for call in mocked.call_args_list))
        self.assertEqual(json.loads(artifact.with_name("AIsland.zip.notary-result.json").read_text())["status"], "Invalid")

    def test_accepted_without_submission_id_does_not_staple(self):
        artifact, target, runner = self.run_attempt([self.submit_result("Accepted", None)])
        with runner as mocked:
            with self.assertRaisesRegex(RuntimeError, "Missing Apple submission ID"):
                module.notarize(artifact, target, "test-profile")
            self.assertEqual(mocked.call_count, 1)

    def test_accepted_with_failed_command_does_not_staple(self):
        artifact, target, runner = self.run_attempt([
            subprocess.CompletedProcess([], 1, json.dumps({"id": "submission-id", "status": "Accepted"}), "error"),
            subprocess.CompletedProcess([], 0),
        ])
        with runner as mocked:
            with self.assertRaisesRegex(RuntimeError, "not accepted"):
                module.notarize(artifact, target, "test-profile")
            self.assertFalse(any("stapler" in call.args[0] for call in mocked.call_args_list))

    def test_malformed_result_does_not_staple(self):
        artifact, target, runner = self.run_attempt([
            subprocess.CompletedProcess([], 0, "[]", ""),
        ])
        with runner as mocked:
            with self.assertRaisesRegex(RuntimeError, "Invalid Apple submission result"):
                module.notarize(artifact, target, "test-profile")
            self.assertEqual(mocked.call_count, 1)

    def test_accepted_must_staple_and_validate(self):
        artifact, target, runner = self.run_attempt([
            self.submit_result("Accepted"), subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0),
        ])
        with runner as mocked:
            module.notarize(artifact, target, "test-profile")
            self.assertEqual(mocked.call_args_list[-2].args[0], ["xcrun", "stapler", "staple", "-v", str(target)])
            self.assertEqual(mocked.call_args_list[-1].args[0], ["xcrun", "stapler", "validate", str(target)])

    def test_invalid_stapled_ticket_fails_release(self):
        artifact, target, runner = self.run_attempt([
            self.submit_result("Accepted"), subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0), subprocess.CalledProcessError(65, ["xcrun", "stapler", "validate"]),
        ])
        with runner:
            with self.assertRaises(subprocess.CalledProcessError):
                module.notarize(artifact, target, "test-profile")


if __name__ == "__main__":
    unittest.main()
