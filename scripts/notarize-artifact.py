#!/usr/bin/env python3
"""Notarize one artifact, retain Apple's result/log, and validate its ticket."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def notarize(artifact: Path, staple_target: Path, profile: str) -> None:
    result_path = artifact.with_name(artifact.name + ".notary-result.json")
    log_path = artifact.with_name(artifact.name + ".notary-log.json")
    print(f"Submitting {artifact.name} to Apple; waiting for the result.", flush=True)
    submitted = subprocess.run([
        "xcrun", "notarytool", "submit", str(artifact),
        "--keychain-profile", profile, "--wait", "--output-format", "json",
    ], capture_output=True, text=True)
    try:
        result = json.loads(submitted.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("Apple returned no valid submission result; no ticket was attached.") from error
    result_path.write_text(json.dumps(result, indent=2) + "\n")
    if not isinstance(result, dict):
        raise RuntimeError(f"Invalid Apple submission result; see {result_path}.")
    submission_id = result.get("id")
    if not isinstance(submission_id, str) or not submission_id:
        raise RuntimeError(f"Missing Apple submission ID; see {result_path}.")
    subprocess.run([
        "xcrun", "notarytool", "log", submission_id,
        "--keychain-profile", profile, str(log_path),
    ], check=True)
    if submitted.returncode != 0 or result.get("status") != "Accepted":
        raise RuntimeError(f"Notarization was not accepted ({result.get('status')}); see {log_path}.")
    subprocess.run(["xcrun", "stapler", "staple", "-v", str(staple_target)], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(staple_target)], check=True)
    print(f"Accepted and ticket validated: {staple_target.name}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("staple_target", type=Path)
    parser.add_argument("profile")
    args = parser.parse_args()
    if not args.artifact.is_file() or not args.staple_target.exists():
        parser.error("The artifact and staple target must exist.")
    try:
        notarize(args.artifact.resolve(), args.staple_target.resolve(), args.profile)
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Notarization failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
