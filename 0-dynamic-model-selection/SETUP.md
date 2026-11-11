# Setup — 0 - Dynamic Model Selection (DMS)

Version 1.5.0. Read this once per host before first use. Steps marked **required** must be done for the feature they name to work.

## 1. Pick the install for your host

| Host | What to run | Result |
|---|---|---|
| Claude Code / Claude desktop on macOS or Linux | `bash scripts/install.sh` | Skill, `/DMS` command, automatic-routing hook |
| Claude Code / Claude desktop on Windows | `powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1` | Same, with the PowerShell hook |
| Claude Code cloud sessions (claude.ai/code) | Add the setup script in section 4 to the environment | Reinstalls on every new session |
| claude.ai / Claude apps (skill upload) | Upload `0 - Dynamic Model Selection.skill` (a zip) in Settings → Capabilities → Skills | Skill only; no hook there |
| Codex, Cursor, Gemini CLI, other agents | Copy this folder to the agent's skills folder (e.g. `~/.agents/skills/0-dynamic-model-selection`), or point the agent's `AGENTS.md` at `SKILL.md` | Skill only; routing per Part B "Other agents" |

Run the installer from inside this folder. Both installers accept: no hook (`--no-hook` / `-NoHook`), no `.agents` copy (`--no-agents` / `-NoAgents`), no slash command (`--no-command` / `-NoCommand`), keep the old `model-selection` skill (`--keep-legacy` / `-KeepLegacy`), and uninstall (`--uninstall` / `-Uninstall`).

**Required (Claude Code / Claude desktop):** `python3` must be on PATH for `install.sh` (it merges `settings.json`). The installer keeps a backup at `settings.json.bak-dms`.

## 2. Load it (required)

Start a new session, or open `/hooks` once in the running session, so Claude Code loads the new skill, command, and hook.

## 3. Verify

1. Type `DMS`. Expected: a status line naming the mode (automatic routing on/off) and the current model.
2. Type any task, e.g. `List the files in this folder`. Expected: a `🔀 Routed: Haiku - …` line before the result.
3. Type `DMS off`, then a task. Expected: no route line. Type `DMS on` to turn it back on.

If step 2 shows no route line, check `~/.claude/settings.json` for a `UserPromptSubmit` entry calling `dms-hook`, then open `/hooks`.

## 4. Claude Code cloud sessions (persistence)

Cloud containers are rebuilt for each session, so files installed by hand disappear. Add this environment setup script (claude.ai/code → environment settings → Setup script):

```bash
if git clone --depth 1 https://github.com/bahattab/Dynamic-Model-Selection /tmp/dms; then
  bash /tmp/dms/0-dynamic-model-selection/scripts/install.sh || true
fi
```

## 5. Automatic routing on and off

The hook stores the on/off state in `~/.config/dms/disabled` (present = off). Change it with `DMS on` / `DMS off`, or set `DMS_STATE_DIR` to move it.

## 6. Uninstall

`bash scripts/install.sh --uninstall` or `.\scripts\install.ps1 -Uninstall`.
