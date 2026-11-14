#!/usr/bin/env python3
"""Integration test for the DMS installers against a throwaway Claude config folder.

Usage:
  python3 tests/test_install.py bash      # scripts/install.sh  (macOS / Linux)
  python3 tests/test_install.py pwsh      # scripts/install.ps1 via pwsh
  python3 tests/test_install.py powershell  # scripts/install.ps1 via Windows PowerShell 5.1

Checks: install twice is idempotent, other settings and hooks survive (including single-item
arrays), a backup is kept, legacy files are removed, the registered hook command actually runs,
--default-off / -DefaultOff sets env DMS_DEFAULT, and uninstall leaves the other settings intact.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILL = ROOT / "0-dynamic-model-selection"
NAME = "0-dynamic-model-selection"
LONG_PROMPT = "Design the event sourcing architecture for the orders and payments services and explain the tradeoffs"

SEED_SETTINGS = {
    "model": "sonnet",
    "permissions": {"allow": ["Bash(ls)"]},
    "env": {"KEEP_ME": "1"},
    "hooks": {
        "UserPromptSubmit": [
            {"hooks": [{"type": "command", "command": "/old/model-routing.sh"}]},
            {"hooks": [{"type": "command", "command": "echo other"}]},
        ],
        "Stop": [{"hooks": [{"type": "command", "command": "echo stop"}]}],
    },
}


def installer(kind, *flags):
    if kind == "bash":
        mapping = {"--uninstall": "--uninstall", "--default-off": "--default-off", "--no-agents": "--no-agents"}
        return ["bash", str(SKILL / "scripts" / "install.sh"), *[mapping[f] for f in flags]]
    mapping = {"--uninstall": "-Uninstall", "--default-off": "-DefaultOff", "--no-agents": "-NoAgents"}
    exe = "pwsh" if kind == "pwsh" else "powershell"
    return [exe, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(SKILL / "scripts" / "install.ps1"),
            *[mapping[f] for f in flags]]


class Check:
    def __init__(self):
        self.failures = 0

    def __call__(self, ok, label):
        print(("ok   " if ok else "FAIL ") + label)
        self.failures += not ok


def dms_entries(settings):
    groups = settings.get("hooks", {}).get("UserPromptSubmit", [])
    return [h for g in groups for h in g.get("hooks", []) if "dms-hook" in h.get("command", "")]


def main():
    kind = sys.argv[1] if len(sys.argv) > 1 else "bash"
    check = Check()
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        claude = tmp / "claude"
        (claude / "skills" / "model-selection").mkdir(parents=True)
        (claude / "skills" / "model-selection" / "SKILL.md").write_text("---\nname: model-selection\n---\n", encoding="utf-8")
        (claude / "hooks").mkdir()
        (claude / "hooks" / "model-routing.sh").write_text("#!/bin/sh\n", encoding="utf-8")
        settings_path = claude / "settings.json"
        settings_path.write_text(json.dumps(SEED_SETTINGS, indent=2), encoding="utf-8")

        env = dict(os.environ, CLAUDE_CONFIG_DIR=str(claude), HOME=str(tmp / "home"), DMS_STATE_DIR=str(tmp / "state"))
        (tmp / "home").mkdir()

        def run(*flags):
            proc = subprocess.run(installer(kind, *flags), capture_output=True, env=env, timeout=120)
            if proc.returncode != 0:
                print(proc.stdout.decode(errors="replace"), proc.stderr.decode(errors="replace"))
            return proc.returncode

        check(run("--no-agents") == 0, "first install exits 0")
        check(run("--no-agents") == 0, "second install exits 0")
        settings = json.loads(settings_path.read_text(encoding="utf-8"))

        check(len(dms_entries(settings)) == 1, "exactly one DMS hook entry after two installs")
        commands = [h["command"] for g in settings["hooks"]["UserPromptSubmit"] for h in g["hooks"]]
        check("echo other" in commands, "other UserPromptSubmit hook kept")
        check(not any("model-routing.sh" in c for c in commands), "legacy model-routing entry removed")
        check(settings["hooks"].get("Stop") == SEED_SETTINGS["hooks"]["Stop"], "Stop hooks unchanged")
        check(settings.get("permissions") == {"allow": ["Bash(ls)"]}, "single-item array kept as a list")
        check(settings.get("model") == "sonnet" and settings.get("env") == {"KEEP_ME": "1"}, "other keys unchanged")
        check((claude / "settings.json.bak-dms").exists(), "settings backup written")
        check(not (claude / "skills" / "model-selection").exists(), "legacy skill folder removed")
        check(not (claude / "hooks" / "model-routing.sh").exists(), "legacy hook file removed")
        installed = claude / "skills" / NAME
        check((installed / "SKILL.md").exists() and (installed / "references" / "guide.md").exists(), "skill and reference guide installed")
        check((claude / "commands" / "DMS.md").exists(), "/DMS command installed")

        # The registered command line must run and produce the clear-win reminder for a long prompt.
        # shell=True is deliberate: Claude Code runs this exact string through a shell, and the string
        # comes from the installer under test (no outside input).
        entry = dms_entries(settings)[0]["command"]
        payload = json.dumps({"prompt": LONG_PROMPT}).encode()
        proc = subprocess.run(entry, shell=True, input=payload, capture_output=True, env=env, timeout=60)
        out = proc.stdout.decode(errors="replace").strip()
        try:
            ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        except Exception:
            ctx = ""
        check(proc.returncode == 0 and "clear win" in ctx, f"registered hook command runs ({entry})")

        check(run("--no-agents", "--default-off") == 0, "install with default-off exits 0")
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        check(settings.get("env", {}).get("DMS_DEFAULT") == "off" and settings["env"].get("KEEP_ME") == "1", "default-off sets env DMS_DEFAULT and keeps other env")

        check(run("--uninstall") == 0, "uninstall exits 0")
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        check(not dms_entries(settings), "uninstall removes DMS hook entry")
        check("DMS_DEFAULT" not in settings.get("env", {}), "uninstall removes DMS_DEFAULT")
        commands = [h["command"] for g in settings.get("hooks", {}).get("UserPromptSubmit", []) for h in g["hooks"]]
        check(commands == ["echo other"], "uninstall keeps the other hook")
        check(not installed.exists() and not (claude / "commands" / "DMS.md").exists(), "uninstall removes skill and command")

    print(f"\n{'all checks passed' if not check.failures else str(check.failures) + ' check(s) failed'} ({kind})")
    return 1 if check.failures else 0


if __name__ == "__main__":
    if shutil.which(sys.argv[1] if len(sys.argv) > 1 else "bash") is None:
        print(f"{sys.argv[1]} not found"); sys.exit(2)
    sys.exit(main())
