#!/usr/bin/env python3
"""Check public update configuration only; never access/create private keys."""
import argparse
import base64
import os
from pathlib import Path
import plistlib
import json
CONFIG = json.loads((Path(__file__).resolve().parent.parent / "config/packaging/AIslandUpdates.json").read_text())

LEGACY = "3IF8txq9RRNanzE2FNhyGRcwhslTucCcJHpTkpxcgBQ="
parser = argparse.ArgumentParser(description=__doc__)
choice = parser.add_mutually_exclusive_group(required=True)
choice.add_argument("--environment", action="store_true")
choice.add_argument("--app", type=Path)
args = parser.parse_args()
if args.environment:
    key = os.environ.get("OPEN_ISLAND_EDDSA_PUBLIC_KEY", "")
    assert os.environ.get("AISLAND_UPDATE_SIGNING_IDENTITY") == "aisland-ed25519-v1", "Explicit AIsland signing identity acknowledgement is required."
else:
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    key = info.get("SUPublicEDKey", "")
    assert info.get("OpenIslandDisableUpdates") is False
    assert info.get("AIslandUpdateSigningIdentity") == "aisland-ed25519-v1"
    assert info.get("SURequireSignedFeed") is True
    assert info.get("SUVerifyUpdateBeforeExtraction") is True
    assert info.get("SUEnableAutomaticChecks") is False
    assert info.get("SUAutomaticallyUpdate") is False
    assert info.get("SUFeedURL") == CONFIG["feed_url"]
assert key == CONFIG["public_key"], "Update public key must match the committed AIsland identity."
assert key and key != LEGACY, "AIsland public key is required; the legacy upstream key is rejected."
assert len(base64.b64decode(key, validate=True)) == 32, "Ed25519 public key must contain exactly 32 bytes."
print("Update public configuration verified. This does not verify a published release or installation.")
