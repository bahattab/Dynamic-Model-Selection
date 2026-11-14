#!/usr/bin/env python3
"""Run tests/hook-cases.json against one DMS hook implementation.

Usage:
  python3 tests/run_hook_tests.py bash 0-dynamic-model-selection/scripts/dms-hook.sh
  python3 tests/run_hook_tests.py pwsh -NoProfile -File 0-dynamic-model-selection/scripts/dms-hook.ps1

Each case runs with a fresh, isolated state directory. Exit code 1 if any case fails.
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

MARKERS = {
    "auto": "route only on a clear win",
    "trigger": "DMS trigger:",
    "on": "turned ON",
    "off": "turned OFF",
}
MAX_CONTEXT_CHARS = 200  # keeps the per-prompt overhead small (about 40-50 tokens)


def state_of(state_dir: pathlib.Path) -> str:
    if (state_dir / "disabled").exists():
        return "disabled"
    if (state_dir / "enabled").exists():
        return "enabled"
    return "none"


def run_case(cmd, case):
    with tempfile.TemporaryDirectory() as tmp:
        state_dir = pathlib.Path(tmp) / "dms"
        state_dir.mkdir()
        before = case.get("state", "none")
        if before != "none":
            (state_dir / before).touch()
        env = {k: v for k, v in os.environ.items() if not k.startswith("DMS_")}
        env["DMS_STATE_DIR"] = str(state_dir)
        env.update(case.get("env", {}))
        payload = json.dumps({"hook_event_name": "UserPromptSubmit", "prompt": case["prompt"]})
        proc = subprocess.run(cmd, input=payload.encode("utf-8"), capture_output=True, env=env, timeout=60)
        out = proc.stdout.decode("utf-8", "replace").strip()
        errors = []
        if proc.returncode != 0:
            errors.append(f"exit code {proc.returncode}: {proc.stderr.decode('utf-8', 'replace').strip()}")
        context = None
        if out:
            try:
                context = json.loads(out)["hookSpecificOutput"]["additionalContext"]
            except (ValueError, KeyError, TypeError) as exc:
                errors.append(f"invalid JSON output ({exc}): {out!r}")
        expect = case["expect"]
        if expect == "none":
            if out:
                errors.append(f"expected no output, got {out!r}")
        elif context is None:
            errors.append(f"expected '{expect}' output, got nothing")
        else:
            if MARKERS[expect] not in context:
                errors.append(f"expected '{expect}' marker in {context!r}")
            if len(context) > MAX_CONTEXT_CHARS:
                errors.append(f"context is {len(context)} chars, cap is {MAX_CONTEXT_CHARS}")
        if "state_after" in case and state_of(state_dir) != case["state_after"]:
            errors.append(f"state after: expected {case['state_after']}, got {state_of(state_dir)}")
        if "log" in case:
            log = state_dir / "routes.log"
            last = log.read_text(encoding="utf-8", errors="replace").strip().splitlines()[-1:] if log.exists() else []
            if not last or not last[0].endswith(" " + case["log"]):
                errors.append(f"log: expected last event '{case['log']}', got {last}")
            if log.exists() and case["prompt"].strip() and case["prompt"].strip() in log.read_text(encoding="utf-8", errors="replace"):
                errors.append("log contains prompt text")
        return errors


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1:]
    cases = json.loads((pathlib.Path(__file__).parent / "hook-cases.json").read_text(encoding="utf-8"))["cases"]
    failed = 0
    for case in cases:
        errors = run_case(cmd, case)
        status = "ok  " if not errors else "FAIL"
        print(f"{status} {case['name']}")
        for err in errors:
            print(f"     - {err}")
        failed += bool(errors)
    print(f"\n{len(cases) - failed}/{len(cases)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
