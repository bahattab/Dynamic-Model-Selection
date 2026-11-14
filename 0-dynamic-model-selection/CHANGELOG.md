# Changelog — 0 - Dynamic Model Selection (DMS)

## 1.7.0 — 2026-11-14
Routing moves into code, so the main model spends no tokens on it.
- **New `dms` mod** (`plugins/dms`, installed from this repo's marketplace): a Claude Code mod that makes the main-model decision in code.
  - Free pre-filter first (word count, then English and Arabic wording hints; other non-Latin prompts always go to the judge); a small Haiku judge runs only when the hint names a different tier. The task is fenced so it cannot close its own tag.
  - Switches the main model automatically on a clear win (confidence ≥ 0.6 up, ≥ 0.75 down) and only while losing the prompt cache stays cheap: context ≤ 40K tokens up, ≤ 150K down (`maxSwitchContextDown`); an unknown size never switches. Otherwise it recommends `/model`.
  - A switch lasts while the task does: the next substantial prompt without a hint for that tier switches back. `/model`, a new pick in the app, or `DMS off` ends it at once.
  - A 3-prompt cooldown prevents flip-flopping and repeated judge calls or recommendations; `/clear` resets it. Switching down to Haiku lowers a `xhigh`/`max` effort to `high`.
- **Subagent conflict fixed:** a model the caller sets is never changed, nor is a typed subagent (it may define its own model). Only a general-purpose subagent with no model, under an Opus parent, may move to a cheaper tier, never up.
- **Merged with the Model Router idea** (claude-code-templates, MIT; notice in `plugins/dms/LICENSE-THIRD-PARTY.md`). Once the `dms` mod is installed, the installers disable the `model-selector` and `model-router` mods, which would make the same decisions twice, and `--uninstall` turns them back on (`--keep-conflicts` / `-KeepConflicts` to skip). No unlicensed third-party code is included.
- **Hook goes quiet when the mod runs:** the mod refreshes a heartbeat per session (`~/.config/dms/mod/<session id>`); while that session's heartbeat is fresh, the hook adds no per-prompt reminder there. Other sessions are unaffected. `DMS on/off` and `DMS <task>` still work.
- **Skill:** trusts only context lines tagged `[dms-mod]` and reports them as `🔀 Switched`, `🔀 Switched back` or `✨ recommended`.
- **Report:** `dms-report.sh` / `.ps1` read `routes.log` and the mod's own `mod.log`, and show the engine in use, main switches and reverts, recommendations, judge calls, hand picks and subagent decisions.
- **Tests:** 42 engine tests for the mod (`claude plugin test`), 7 new hook cases, and installer checks for the mod, failed installs, `--no-mod`, `--keep-conflicts` and conflict re-enabling; CI gains a mod job pinned to Claude Code 2.1.325.
- **Review:** a council and red-team pass on this release fixed the findings above before release.

## 1.6.0 — 2026-11-14
Cost-first release from the council review of 1.5.0.
- **Clear-win gate:** answer in place by default; route only when the needed tier differs from the current model and the task is large or opus-grade. Same-tier delegation is never done.
- **Slim skill:** `SKILL.md` is now a short core (~3K → ~1K tokens); tie-breaks, examples, host adapters and Tier 1 pipeline categories moved to `references/guide.md`, loaded on demand.
- **Cheaper hook:** prompts under `DMS_MIN_WORDS` (default 12) get no injection; longer ones get one line (≤ 200 characters). Toggles are exact (`DMS on`, `DMS off`, optional `.`/`!`); bash and PowerShell now behave the same.
- **Default control:** `DMS_DEFAULT=off` (or `install.sh --default-off` / `install.ps1 -DefaultOff`) ships with automatic routing off; an `enabled`/`disabled` state file still wins.
- **Route log and report:** the hook logs `inject`, `skip`, `trigger`, `on`, `off` events and the model logs real routes to `~/.config/dms/routes.log` (no prompt text); `scripts/dms-report.sh` / `dms-report.ps1` summarise it for `DMS status`.
- **Windows:** the hook is registered as `powershell -NoProfile -ExecutionPolicy Bypass -File …`; `settings.json` is written atomically.
- **No hidden failures:** the registered hook command no longer ends in `2>/dev/null || true`.
- **Tests and release gate:** one shared case table (`tests/hook-cases.json`) runs against both hooks; installer integration tests; shellcheck, PSScriptAnalyzer and a version-consistency check. The new `Test` workflow runs on Linux and Windows and must pass before `Release` publishes.
- **Supply chain:** the cloud setup script is pinned to a release tag.

## 1.5.0 — 2026-11-11
- Renamed to **0 - Dynamic Model Selection** (ID `0-dynamic-model-selection`); `model-selection` kept as a legacy alias.
- Trigger `DMS` (case-insensitive), `/DMS` slash command, `DMS on` / `DMS off` / `DMS status`.
- Hook rewritten (`scripts/dms-hook.sh`, `scripts/dms-hook.ps1`): on/off state, DMS trigger detection; the prompt text is never echoed.
- Installers for macOS/Linux (`install.sh`) and Windows (`install.ps1`) with merge-safe `settings.json` update, backup, legacy cleanup, and uninstall.
- Portable to any Markdown-capable agent: host adapters for Claude Code and other agents; `agents/openai.yaml` metadata.
- Added `SETUP.md` and a cloud-session setup script.

## 1.4.0
- Auto-Routing Mode: route each prompt by complexity without `/model`, driven by a `UserPromptSubmit` hook.

## 1.3.0
- Conversation routing: start a new conversation on the chosen model and verify it before reporting the switch.

## 1.2.0
- Tier gate works in Claude desktop / Claude Code (runtime detection via `CLAUDECODE=1` and a subagent tool with `model`).
- Non-Claude fallbacks replaced with Claude models; subagent dispatch rules; tie-break rules.

## 1.1.0
- Full model IDs, fallback procedure, escalation rule, worked examples.

## 1.0.0
- Merged `model-selection` (haiku/sonnet/opus criteria) and `sk-dynamic-routing` (Tier 1 categories) into one skill.
