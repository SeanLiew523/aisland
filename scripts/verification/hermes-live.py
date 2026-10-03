#!/usr/bin/env python3
"""Real Hermes CLI verification with a disposable home and metadata-only socket.

No hook consent is granted here. Run `run` in a TTY and let the human answer
Hermes' own first-use prompts. Nothing reads unrelated sessions or auth stores.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import socket
import tempfile
import time

PROMPT = "Reply only AISLAND-HERMES-OK, don't call tools."
FIELDS = {
    "source", "event", "profile_id", "session_id", "turn_id", "sequence",
    "cwd", "timestamp", "terminal_app", "terminal_session_id", "terminal_tty",
    "app_bundle_id", "app_conversation_id", "source_observed_start",
    "navigation_socket_path", "result_reason", "tmux_target", "tmux_socket_path",
    "warp_pane_uuid",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def private_write(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(value)


def prepare(args):
    import yaml
    source = Path(args.source_home).resolve()
    source_config = source / "config.yaml"
    config = yaml.safe_load(source_config.read_text())
    model = config.get("model", {})
    # This probe is scoped to the installed user's current zhipu custom route.
    # Never infer or silently switch account/provider after a source change.
    if not isinstance(model, dict) or model.get("provider") != "zhipu":
        raise SystemExit("Current provider changed; review its auth route before reuse.")
    selected = [entry for entry in config.get("custom_providers", [])
                if isinstance(entry, dict) and
                str(entry.get("name", "")).strip().lower().replace(" ", "-") == "zhipu"]
    if len(selected) != 1 or not selected[0].get("api_key"):
        raise SystemExit("The selected vendor has no unique saved API-key route; human authentication required.")
    # Refuse external secret references rather than reading additional secret stores.
    if "${" in str(selected[0]["api_key"]) or selected[0].get("key_cmd"):
        raise SystemExit("Selected auth requires an external secret source; review before reuse.")
    root = Path(tempfile.mkdtemp(prefix="aisland-hermes-", dir="/tmp")).resolve()
    home = root / "home"
    cwd = root / "task"
    home.mkdir(mode=0o700)
    cwd.mkdir(mode=0o700)
    binary = root / "OpenIslandHooks"
    shutil.copy2(args.hooks_binary, binary)
    binary.chmod(0o700)
    command = f"{shlex.quote(str(binary))} --source hermes --profile-id {shlex.quote(str(home))}"
    isolated = {"model": model, "custom_providers": selected,
                "hooks": {event: [{"command": command, "timeout": 3, "fail_closed": False}]
                          for event in ("pre_llm_call", "on_session_end")}}
    private_write(home / "config.yaml", yaml.safe_dump(isolated, sort_keys=False))
    # A present empty env file prevents accidental root-profile dotenv inheritance.
    private_write(home / ".env", "# Dedicated metadata-only verification home.\n")
    metadata = {"root": str(root), "home": str(home), "cwd": str(cwd),
                "socket": str(root / "bridge.sock"), "hooks_binary_sha256": digest(binary),
                "source_config_sha256": digest(source_config),
                "source_home": str(source), "model": model.get("default"),
                "provider": model.get("provider"), "prompt": PROMPT,
                "source_commit": args.source_commit, "app_source_commit": args.app_source_commit}
    private_write(root / "metadata.json", json.dumps(metadata, indent=2) + "\n")
    print(str(root))


def metadata(root):
    return json.loads((root / "metadata.json").read_text())


def collect(args):
    root = Path(args.root).resolve()
    data = metadata(root)
    path = Path(data["socket"])
    # Never unlink a pre-existing path: this collector owns only its new socket.
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(path))
    path.chmod(0o600)
    listener.listen(8)
    listener.settimeout(1)
    output = root / "receipts.jsonl"
    if not output.exists():
        private_write(output, "")
    deadline = time.monotonic() + args.seconds
    print(json.dumps({"collector": "ready", "socket": str(path)}), flush=True)
    try:
        while time.monotonic() < deadline and not (root / "stop").exists():
            try:
                connection, _ = listener.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(2)
                raw = bytearray()
                while b"\n" not in raw:
                    chunk = connection.recv(4096)
                    if not chunk:
                        break
                    raw.extend(chunk)
                    if len(raw) > 65536:
                        raise RuntimeError("Oversized envelope rejected without persistence.")
                envelope = json.loads(raw.split(b"\n", 1)[0])
                command = envelope.get("command", {})
                payload = command.get("runtimeLifecycleHook", {})
                unexpected = set(payload) - FIELDS
                if (set(envelope) != {"type", "command"} or
                        set(command) != {"type", "runtimeLifecycleHook"} or
                        envelope.get("type") != "command" or
                        command.get("type") != "processRuntimeLifecycleHook" or unexpected):
                    raise RuntimeError("Non-metadata envelope rejected without persistence.")
                if (payload.get("source") != "hermesCLI" or payload.get("profile_id") != data["home"] or
                        Path(payload.get("cwd", "")).resolve() != Path(data["cwd"]).resolve()):
                    raise RuntimeError("Unrelated runtime envelope rejected without persistence.")
                with output.open("a") as handle:
                    handle.write(json.dumps(payload, sort_keys=True) + "\n")
                connection.sendall(b'{"type":"response","response":{"type":"acknowledged"}}\n')
                print(json.dumps({"event": payload.get("event"), "receipt_fields": sorted(payload)}), flush=True)
    finally:
        listener.close()
        path.unlink(missing_ok=True)


def run(args):
    data = metadata(Path(args.root).resolve())
    env = {key: os.environ[key] for key in ("HOME", "PATH", "USER", "LOGNAME", "SHELL", "LANG", "LC_ALL", "TERM", "TERM_PROGRAM", "TERM_SESSION_ID", "ITERM_SESSION_ID", "TTY", "TMUX", "TMUX_PANE", "SSH_TTY") if key in os.environ}
    env.update({"HERMES_HOME": data["home"], "OPEN_ISLAND_SOCKET_PATH": data["socket"]})
    os.chdir(data["cwd"])
    # -Q implies answer-and-exit but retains the real stdin TTY consent prompts.
    # ignore-rules skips personal instructions/memory; it does not skip lifecycle hooks.
    os.execve(args.hermes, [args.hermes, "chat", "-Q", "-q", PROMPT,
                           "--ignore-rules", "--max-turns", "1", "--run-budget", "90"], env)


def summary(args):
    root = Path(args.root).resolve()
    data = metadata(root)
    receipts = [json.loads(line) for line in (root / "receipts.jsonl").read_text().splitlines()]
    starts = [r for r in receipts if r.get("event") == "turnStarted"]
    ends = [r for r in receipts if r.get("event") in {"turnCompleted", "turnFailed", "turnInterrupted"}]
    pairs = [(s, e) for s in starts for e in ends if s.get("session_id") == e.get("session_id") and s.get("turn_id") == e.get("turn_id")]
    result = {"receipts": len(receipts), "starts": len(starts), "ends": len(ends),
              "matching_turn_pairs": len(pairs), "outcomes": [e["event"] for e in ends],
              "only_metadata_fields": all(set(r) <= FIELDS for r in receipts),
              "source_config_unchanged": digest(Path(data["source_home"]) / "config.yaml") == data["source_config_sha256"],
              "terminal_metadata_fields": sorted({key for r in receipts for key in r if key.startswith("terminal_") or key in {"tmux_target", "warp_pane_uuid"}})}
    print(json.dumps(result, indent=2))


parser = argparse.ArgumentParser(description=__doc__)
sub = parser.add_subparsers(dest="mode", required=True)
p = sub.add_parser("prepare")
p.add_argument("--source-home", required=True)
p.add_argument("--hooks-binary", required=True)
p.add_argument("--source-commit", required=True)
p.add_argument("--app-source-commit", required=True)
p = sub.add_parser("collect")
p.add_argument("root")
p.add_argument("--seconds", type=int, default=300)
p = sub.add_parser("run")
p.add_argument("root")
p.add_argument("--hermes", default=str(Path.home() / ".local/bin/hermes"))
p = sub.add_parser("summary")
p.add_argument("root")
args = parser.parse_args()
globals()[args.mode](args)
