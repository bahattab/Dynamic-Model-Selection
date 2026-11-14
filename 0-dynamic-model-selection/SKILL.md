---
name: 0-dynamic-model-selection
description: |
  Trigger on "DMS" (case-insensitive), "/DMS", "0 - Dynamic Model Selection",
  $0-dynamic-model-selection, or the legacy alias "model-selection". Routes a task to haiku,
  sonnet, or opus only when that clearly saves cost or is needed for quality; otherwise the
  task is answered in place. Use when choosing subagent models, routing large or opus-grade
  work, turning automatic routing on or off ("DMS on" / "DMS off"), or checking routing
  savings ("DMS status"). Portable to any Markdown-capable agent; switching models depends
  on host support.
metadata:
  version: 1.6.0
  display-name: 0 - Dynamic Model Selection
  trigger: DMS
  legacy-aliases: model-selection, sk-dynamic-routing
---
# 0 - Dynamic Model Selection (DMS)

Goal: lower cost without losing quality. **The default is to answer in place.** Route only on a clear win.

Details (tie-breaks, examples, host adapters, Tier 1 pipeline categories) are in `references/guide.md`. Read it only when a case below is unclear or a pipeline role is involved. First-time setup: `SETUP.md`.

## Commands (case-insensitive)

| User types | Action |
|---|---|
| `DMS <task>` / `/DMS <task>` | Apply the gate and route the task if it passes. |
| `DMS` / `DMS status` | Report mode (on/off), routing tools, current model, and the route-log summary (`scripts/dms-report.sh` if a shell is available). |
| `DMS on` / `DMS off` | Confirm in one line; the hook stores the setting. |

## 1. Classify (3 steps, stop at the first match)

1. **Opus:** a decision across several components, or costly to reverse (architecture, migration strategy, novel algorithm).
2. **Haiku:** read-only and no judgment (search, list, validate, simple transform).
3. **Sonnet:** everything else (code changes, fixes, tests, reviews within one component).

Model IDs: `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5` (aliases `haiku`, `sonnet`, `opus`). Use the host's current IDs for the same tiers.

## 2. Clear-win gate (apply before any routing)

Route **only if** one of these holds; otherwise answer in place and print **no** route line:

- **Up:** the task needs a higher tier than the current model (e.g. opus-grade work in a sonnet conversation).
- **Down:** the task is large, self-contained and read-heavy (e.g. a broad scan across many files) and a cheaper tier fits.

Never route when the chosen tier equals the current model, or for quick questions, short edits, or anything that needs this conversation's context. A subagent starts with no context, re-reads files and relays results; that overhead must be smaller than the saving.

**Biggest saving:** keep the main conversation on sonnet. It answers most work in place and routes only opus-grade work up.

## 3. Route (when the gate passes)

- **Subagent** (Claude Code / Claude desktop): Agent tool with `model` = alias; always pass it. Forked subagents ignore `model`.
- **New conversation** (cloud sessions, long independent work): `create_session` with the full model ID; verify with `get_session` → `session_context.model` before reporting.
- **Current conversation:** only the user can switch it (`/model <id>`); recommend, never claim.
- **Other agents:** use the host's equivalent tier if it can set a task's model; otherwise recommend.
- **Escalate on evidence:** if a result fails verification, re-run one tier up.

Report before the result: `🔀 Routed: <Model> - <reason>`. Recommendation only: `✨ <Model> recommended - <reason>`.

## 4. Log routes (when a shell is available)

After each real route, append one line (no prompt text):

```bash
printf '%s route %s %s\n' "$(date -u +%FT%TZ)" <tier> <subagent|session> >> "${DMS_STATE_DIR:-$HOME/.config/dms}/routes.log"
```

The hook logs its own events (`inject`, `skip`, `trigger`, `on`, `off`) to the same file.

## Truthfulness

Report a switch only after it is verified. Never claim a subagent, a new conversation, or a model change that did not happen. If the host cannot run another model, say so and recommend.
