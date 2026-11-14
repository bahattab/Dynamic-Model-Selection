# Changelog — 0 - Dynamic Model Selection (DMS)

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
