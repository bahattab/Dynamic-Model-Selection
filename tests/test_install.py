#!/usr/bin/env python3
"""Integration test for the DMS installers against a throwaway Claude config folder.

Usage:
  python3 tests/test_install.py bash      # scripts/install.sh  (macOS / Linux)
  python3 tests/test_install.py pwsh      # scripts/install.ps1 via pwsh
  python3 tests/test_install.py powershell  # scripts/install.ps1 via Windows PowerShell 5.1

Checks: install twice is idempotent, other settings and hooks survive (including single-item
arrays), a backup is kept, legacy files are removed, the registered hook command actually runs,
--default-off / -DefaultOff sets env DMS_DEFAULT, the DMS mod is installed and the conflicting
model-selector / model-router mods are disabled (through a fake `claude` CLI that records its calls),
and uninstall leaves the other settings intact.
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
        mapping = {"--uninstall": "--uninstall", "--default-off": "--default-off", "--no-agents": "--no-agents", "--no-mod": "--no-mod", "--keep-conflicts": "--keep-conflicts"}
        return ["bash", str(SKILL / "scripts" / "install.sh"), *[mapping[f] for f in flags]]
    mapping = {"--uninstall": "-Uninstall", "--default-off": "-DefaultOff", "--no-agents": "-NoAgents", "--no-mod": "-NoMod", "--keep-conflicts": "-KeepConflicts"}
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

        bindir = tmp / "bin"
        bindir.mkdir()
        calls = tmp / "claude-calls.log"
        listing = tmp / "plugin-list.txt"
        listing.write_text("  > model-router@claude-model-selector\n  > model-selector@claude-model-selector\n  > handoff@claude-model-selector\n", encoding="utf-8")
        # The fake CLI records each call, prints the listing for `plugin list`, writes a stderr line
        # (as the real one may), and fails `plugin install` while FAKE_CLAUDE_FAIL is set.
        if os.name == "nt":
            lines = ["@echo off", '>>"%FAKE_CLAUDE_LOG%" echo %*', 'if "%1 %2"=="plugin list" type "%FAKE_CLAUDE_LIST%"',
                     "echo note on stderr 1>&2", 'if "%1 %2"=="plugin install" if defined FAKE_CLAUDE_FAIL exit /b 1', "exit /b 0"]
            (bindir / "claude.cmd").write_text("\r\n".join(lines) + "\r\n", encoding="ascii")
        else:
            fake = bindir / "claude"
            fake.write_text('#!/bin/sh\necho "$*" >> "$FAKE_CLAUDE_LOG"\n[ "$1 $2" = "plugin list" ] && cat "$FAKE_CLAUDE_LIST"\n'
                            'echo "note on stderr" >&2\n[ "$1 $2" = "plugin install" ] && [ -n "${FAKE_CLAUDE_FAIL:-}" ] && exit 1\nexit 0\n', encoding="utf-8")
            fake.chmod(0o755)
        env = dict(os.environ, CLAUDE_CONFIG_DIR=str(claude), HOME=str(tmp / "home"), DMS_STATE_DIR=str(tmp / "state"),
                   FAKE_CLAUDE_LOG=str(calls), FAKE_CLAUDE_LIST=str(listing), PATH=str(bindir) + os.pathsep + os.environ.get("PATH", ""))
        (tmp / "home").mkdir()

        last = {"out": ""}

        def run(*flags):
            proc = subprocess.run(installer(kind, *flags), capture_output=True, env=env, timeout=120)
            last["out"] = proc.stdout.decode(errors="replace") + proc.stderr.decode(errors="replace")
            if proc.returncode != 0:
                print(last["out"])
            return proc.returncode

        def fresh_calls():
            if calls.exists():
                calls.unlink()

        def made_calls():
            return calls.read_text(encoding="utf-8", errors="replace") if calls.exists() else ""

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
        made = calls.read_text(encoding="utf-8", errors="replace") if calls.exists() else ""
        check("plugin marketplace add" in made and "plugin install dms@dynamic-model-selection" in made, "DMS mod installed through the claude CLI")
        check("plugin disable model-router@claude-model-selector" in made and "plugin disable model-selector@claude-model-selector" in made,
              "conflicting model-router and model-selector mods disabled")
        check("handoff@claude-model-selector" not in made.replace("plugin list", ""), "non-conflicting mods left alone")
        check("plugin list" in made, "installed plugins listed before disabling")
        record = tmp / "state" / "disabled-conflicts"
        recorded = record.read_text(encoding="utf-8") if record.exists() else ""
        check("model-router@claude-model-selector" in recorded and "model-selector@claude-model-selector" in recorded,
              "disabled mods recorded for --uninstall")

        # The registered command line must run and produce the clear-win reminder for a long prompt.
        # shell=True is deliberate: Claude Code runs this exact string through a shell, and the string
        # comes from the installer under test (no outside input).
        entries = dms_entries(settings)
        if entries:
            entry = entries[0]["command"]
            payload = json.dumps({"prompt": LONG_PROMPT}).encode()
            proc = subprocess.run(entry, shell=True, input=payload, capture_output=True, env=env, timeout=60)
            out = proc.stdout.decode(errors="replace").strip()
            try:
                ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"]
            except Exception:
                ctx = ""
            check(proc.returncode == 0 and "clear win" in ctx, f"registered hook command runs ({entry})")
        else:
            check(False, "registered hook command runs (no DMS entry found)")

        check(run("--no-agents", "--default-off") == 0, "install with default-off exits 0")
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        check(settings.get("env", {}).get("DMS_DEFAULT") == "off" and settings["env"].get("KEEP_ME") == "1", "default-off sets env DMS_DEFAULT and keeps other env")

        # Only one conflict listed, with another bullet: the missing one must not stop the installer.
        listing.write_text("\u276f model-router@claude-model-selector\n", encoding="utf-8")
        fresh_calls()
        check(run("--no-agents") == 0, "install exits 0 when only one conflicting mod is listed")
        made = made_calls()
        check("plugin disable model-router@claude-model-selector" in made and "plugin disable model-selector" not in made,
              "only the listed conflicting mod is disabled")

        fresh_calls()
        env["FAKE_CLAUDE_FAIL"] = "1"
        check(run("--no-agents") == 0, "a failed mod install does not fail the installer")
        check("install FAILED" in last["out"], "a failed mod install is reported")
        check("plugin disable" not in made_calls(), "no mod is disabled when the DMS mod did not install")
        del env["FAKE_CLAUDE_FAIL"]

        fresh_calls()
        check(run("--no-agents", "--no-mod") == 0, "install with --no-mod exits 0")
        check("plugin install" not in made_calls(), "--no-mod skips the DMS mod")

        fresh_calls()
        check(run("--no-agents", "--keep-conflicts") == 0, "install with --keep-conflicts exits 0")
        made = made_calls()
        check("plugin install dms@dynamic-model-selection" in made and "plugin disable" not in made, "--keep-conflicts leaves other mods on")

        check(run("--uninstall") == 0, "uninstall exits 0")
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        check(not dms_entries(settings), "uninstall removes DMS hook entry")
        check("DMS_DEFAULT" not in settings.get("env", {}), "uninstall removes DMS_DEFAULT")
        commands = [h["command"] for g in settings.get("hooks", {}).get("UserPromptSubmit", []) for h in g["hooks"]]
        check(commands == ["echo other"], "uninstall keeps the other hook")
        check(not installed.exists() and not (claude / "commands" / "DMS.md").exists(), "uninstall removes skill and command")
        made = calls.read_text(encoding="utf-8", errors="replace")
        check("plugin uninstall dms@dynamic-model-selection" in made, "uninstall removes the DMS mod")
        check("plugin enable model-router@claude-model-selector" in made and "plugin enable model-selector@claude-model-selector" in made,
              "uninstall turns the disabled mods back on")
        check(not record.exists(), "uninstall clears the record of disabled mods")

    print(f"\n{'all checks passed' if not check.failures else str(check.failures) + ' check(s) failed'} ({kind})")
    return 1 if check.failures else 0


if __name__ == "__main__":
    if shutil.which(sys.argv[1] if len(sys.argv) > 1 else "bash") is None:
        print(f"{sys.argv[1]} not found"); sys.exit(2)
    sys.exit(main())
