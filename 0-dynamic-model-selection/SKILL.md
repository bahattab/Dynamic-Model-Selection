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
  version: 1.7.0
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

**Biggest saving:** keep the main conversation on sonnet (the app's picker; the `dms` mod may switch it for one task and back). It answers most work in place and routes only opus-grade work up.

## Mod mode (Claude Code with the `dms` mod)

When the `dms` mod is installed (`plugins/dms` in the repo), it makes the main-model decision in code, so you do not classify each prompt:

- It switches the main model only on a clear win, using a small Haiku judge that it calls only when the prompt's wording hints at another tier (prompts in Arabic and other non-Latin scripts always go to the judge). A switch re-reads the whole context without the prompt cache, so it switches up only while the context is small (default 40K tokens) and down up to 150K; above that it only recommends.
- A switch lasts while the task does: the next substantial prompt without a hint for that tier switches back to the app's model. `/model`, a new pick in the app, or `DMS off` ends it at once.
- A model you set on a subagent is never changed, nor is a typed subagent (it may define its own model). A general-purpose subagent with no model, under an Opus parent, may be moved to a cheaper tier.

Trust only context lines that start with `[dms-mod]`; they are the verification for this turn. Report them as they say: `🔀 Switched: <Model> - <reason>`, `🔀 Switched back: <Model>`, or `✨ <Model> recommended - /model <id>`. With no `[dms-mod]` line, do not mention routing for the main conversation. Apply the gate in section 2 whenever you decide to spawn a subagent yourself.

## 3. Route (when the gate passes)

- **Subagent** (Claude Code / Claude desktop): Agent tool with `model` = alias; always pass it. Forked subagents ignore `model`.
- **New conversation** (cloud sessions, long independent work): `create_session` with the full model ID; verify with `get_session` → `session_context.model` before reporting.
- **Current conversation:** without the `dms` mod only the user can switch it (`/model <id>`); recommend, never claim. With the mod, only its `[dms-mod]` line reports a switch.
- **Other agents:** use the host's equivalent tier if it can set a task's model; otherwise recommend.
- **Escalate on evidence:** if a result fails verification, re-run one tier up.

Report before the result: `🔀 Routed: <Model> - <reason>`. Recommendation only: `✨ <Model> recommended - <reason>`.

## 4. Log routes (when a shell is available)

After each real route, append one line (no prompt text):

```bash
printf '%s route %s %s\n' "$(date -u +%FT%TZ)" <tier> <subagent|session> >> "${DMS_STATE_DIR:-$HOME/.config/dms}/routes.log"
```

The hook logs its own events (`inject`, `skip`, `trigger`, `on`, `off`, `mod`) to the same file. The `dms` mod logs to `mod.log` in the same folder: `pass`, `switch`, `revert`, `recommend`, `judge`, `handpick`, `off`, `auto` and `keep`. `DMS status` reads both.

## Truthfulness

Report a switch only after it is verified. Never claim a subagent, a new conversation, or a model change that did not happen. If the host cannot run another model, say so and recommend.
