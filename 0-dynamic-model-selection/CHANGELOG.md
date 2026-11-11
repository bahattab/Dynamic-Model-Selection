# Changelog — 0 - Dynamic Model Selection (DMS)

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
