# Setup — 0 - Dynamic Model Selection (DMS)

Version 1.7.0. Read this once per host before first use. Steps marked **required** must be done for the feature they name to work.

## 1. Pick the install for your host

| Host | What to run | Result |
|---|---|---|
| Claude Code / Claude desktop on macOS or Linux | `bash scripts/install.sh` (from a clone of the repo) | Skill, `/DMS` command, hook, and the `dms` mod |
| Claude Code / Claude desktop on Windows | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1` (from a clone) | Same, with the PowerShell hook |
| Claude Code cloud sessions (claude.ai/code) | Add the setup script in section 4 to the environment | Reinstalls on every new session |
| claude.ai / Claude apps (skill upload) | Upload `0 - Dynamic Model Selection.skill` (a zip) in Settings → Capabilities → Skills | Skill only; no hook there |
| Codex, Cursor, Gemini CLI, other agents | Copy this folder to the agent's skills folder (e.g. `~/.agents/skills/0-dynamic-model-selection`), or point the agent's `AGENTS.md` at `SKILL.md` | Skill only |

Run the installer from inside this folder. Options (bash / PowerShell):

| Option | Effect |
|---|---|
| `--no-hook` / `-NoHook` | Skill and command only |
| `--no-agents` / `-NoAgents` | Skip the `~/.agents/skills` copy |
| `--no-command` / `-NoCommand` | Skip the `/DMS` slash command |
| `--no-mod` / `-NoMod` | Skip the `dms` mod (hook + skill only) |
| `--keep-conflicts` / `-KeepConflicts` | Leave `model-selector` / `model-router` mods enabled |
| `--default-off` / `-DefaultOff` | Ship with automatic routing off (`env.DMS_DEFAULT=off` in settings.json) |
| `--keep-legacy` / `-KeepLegacy` | Keep the old `model-selection` skill |
| `--uninstall` / `-Uninstall` | Remove everything DMS added |

**Required (macOS / Linux):** `python3` on PATH (the installer uses it to merge `settings.json`). A backup is kept at `settings.json.bak-dms`.

## 1b. The `dms` mod (Claude Code)

The installers add the mod when the `claude` CLI is on PATH and they run from a clone of the repository. To add it by hand:

```
/plugin install dms --marketplace bahattab/Dynamic-Model-Selection
```

The mod switches the main model on a clear win while the context is small, keeps every subagent model the caller sets, and may move an unset subagent of an Opus parent to a cheaper tier. Settings (`/plugin configure dms@dynamic-model-selection`): `switchMain`, `maxSwitchContext` (40000), `minWords` (12), `cooldownPrompts` (3), `upConfidence` (0.6), `downConfidence` (0.75), `routeUnsetSubagents`, `timeoutMs`, and the three tier model ids.

**Other routing mods.** `model-selector` and `model-router` (from other mod packs) make the same decisions and would override DMS, so the installers disable them. `handoff` and `cache-clock` do not conflict.

## 2. Load it (required)

Start a new session, or open `/hooks` once in the running session, so Claude Code loads the skill, command and hook.

## 3. Verify

1. Type `DMS status`. Expected: the mode (on/off), the engine (mod or hook), the current model, and the route-log summary.
2. Type `thanks`. Expected: no route line and no DMS text (short prompts are skipped).
3. In a **sonnet** conversation, type a large opus-grade task, e.g. `Design the event-sourcing architecture for the orders and payments services and explain the tradeoffs`. Expected: a `🔀 Routed: Opus - …` line.
4. Type `DMS off`, repeat step 3. Expected: no route line. `DMS on` turns it back on.

If step 3 shows no route line with routing on, check `~/.claude/settings.json` for a `UserPromptSubmit` entry calling `dms-hook`, then open `/hooks`.

## 4. Claude Code cloud sessions (persistence)

Cloud containers are rebuilt for each session. Add this environment setup script (claude.ai/code → environment settings → Setup script). It is pinned to a release tag; update the tag when you adopt a new release.

```bash
if git clone -q --depth 1 --branch v1.7.0 https://github.com/bahattab/Dynamic-Model-Selection /tmp/dms; then
  bash /tmp/dms/0-dynamic-model-selection/scripts/install.sh || echo "DMS install FAILED" >&2
else
  echo "DMS download FAILED" >&2
fi
```

To ship cloud sessions with routing off, add `--default-off` to the `install.sh` line, or set `DMS_DEFAULT=off` in the environment variables.

## 5. Settings

| Setting | Default | Meaning |
|---|---|---|
| `DMS on` / `DMS off` | — | Stored in `~/.config/dms/enabled` / `disabled`; wins over `DMS_DEFAULT` |
| `DMS_DEFAULT` | `on` | Mode when neither state file exists (`off`, `0`, `false`, `no` = off) |
| `DMS_MIN_WORDS` | `12` | Prompts with fewer words get no injection |
| `DMS_STATE_DIR` | `~/.config/dms` | Where the state files and `routes.log` live |

## 6. Route log

`~/.config/dms/routes.log` holds one line per event (`inject`, `skip`, `trigger`, `on`, `off`, `route <tier> <subagent|session>`), never prompt text. Summarise it with `bash scripts/dms-report.sh` (Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dms-report.ps1`). Delete the file to reset it.

## 7. Uninstall

`bash scripts/install.sh --uninstall` or `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Uninstall`.
