# 0 - Dynamic Model Selection (DMS)

**Version 1.7.0** · Agent skill + Claude Code mod · Trigger: `DMS`

DMS cuts model cost by sending a task to a different Claude model **only when that clearly pays off**: Opus for architecture and hard-to-reverse decisions in a Sonnet conversation, a cheaper model for a large read-heavy scan. Everything else is answered in place, because a subagent starts with no context and its overhead often costs more than it saves. Every real route is reported and logged.

In Claude Code, the `dms` mod makes these decisions in code, so the main model spends no tokens on routing. Everywhere else it is a standard `SKILL.md` skill that any Markdown-capable agent can use. Running work on another model depends on what the host supports; where that isn't possible, DMS recommends instead of claiming a switch.

---

## Contents

- [How it works](#how-it-works)
- [Commands](#commands)
- [Install](#install)
- [Verify](#verify)
- [Routing rules](#routing-rules)
- [Measuring savings](#measuring-savings)
- [Host support](#host-support)
- [Repository layout](#repository-layout)
- [Testing](#testing)
- [Limitations](#limitations)
- [Versioning](#versioning)
- [Related skills](#related-skills)

---

## How it works

**With the `dms` mod (Claude Code):**

```
your prompt
   │
   ├─ < 12 words, or no wording hint for another tier .... nothing, no cost
   ├─ hint names another tier (or non-Latin script) ....... one small Haiku judge call
   │      confident (≥ 0.6 up / ≥ 0.75 down) and context ≤ 40K up / 150K down → switch the main model
   │      confident but context larger ......................... one line recommending /model
   ├─ later prompt with no hint for the switched tier ...... switch back to the app's model
   ├─ /model, a new pick in the app, or DMS off ............ the switch ends at once
   └─ subagent spawn
          model set by the caller, or a typed agent ...... never changed
          no model, general-purpose, Opus parent ......... judge may pick a cheaper tier
```

**Without the mod (other hosts, or the hook only):**

```
your prompt
   │
   ├─ UserPromptSubmit hook (Claude Code)
   │     short prompt (< 12 words) ......... nothing added, no cost
   │     longer prompt ..................... one line: "route only on a clear win"
   │     "DMS ..." ......................... load the skill for this task
   │
   ▼
Classify ── opus check → haiku check → sonnet by default
   │
   ▼
Clear-win gate
   ├─ needed tier = current model ......... answer in place (no route line)
   ├─ needs a higher tier ................. subagent / new conversation on that tier
   └─ large, read-heavy, cheaper tier fits  subagent on the cheaper tier
   │
   ▼
🔀 Routed: Opus - cross-service architecture      ← only when a route happened
```

The biggest saving is the conversation's own model: keep it on Sonnet, and let DMS send only opus-grade work up.

## Commands

| You type | Effect |
|---|---|
| `DMS <task>` or `/DMS <task>` | Apply the gate to this task and route it if it passes |
| `DMS` / `DMS status` | Mode, routing tools, current model, route-log summary |
| `DMS on` / `DMS off` | Turn automatic routing on or off (exact match) |

Case-insensitive. Other names that load the skill: `0 - Dynamic Model Selection`, `$0-dynamic-model-selection`, and the legacy alias `model-selection`.

## Install

**The `dms` mod (Claude Code):**

```
/plugin install dms --marketplace bahattab/Dynamic-Model-Selection
```

The installers below add it for you when the `claude` CLI is on PATH.

**macOS / Linux (Claude Code, Claude desktop)**

```bash
git clone https://github.com/bahattab/Dynamic-Model-Selection
```

```bash
bash Dynamic-Model-Selection/0-dynamic-model-selection/scripts/install.sh
```

**Windows (Claude Code, Claude desktop)**

```powershell
git clone https://github.com/bahattab/Dynamic-Model-Selection
powershell -NoProfile -ExecutionPolicy Bypass -File .\Dynamic-Model-Selection\0-dynamic-model-selection\scripts\install.ps1
```

The installer puts:

| Path | Purpose |
|---|---|
| `~/.claude/skills/0-dynamic-model-selection/` | Skill for Claude Code / Claude desktop |
| `~/.agents/skills/0-dynamic-model-selection/` | Shared skills folder for other agents |
| `~/.claude/commands/DMS.md` | `/DMS` slash command |
| `~/.claude/hooks/dms-hook.sh` (`.ps1` on Windows) | Automatic-routing hook |
| `~/.claude/settings.json` | `UserPromptSubmit` entry, merged with existing settings; backup at `settings.json.bak-dms` |

Options: `--no-hook`, `--no-agents`, `--no-command`, `--no-mod`, `--keep-conflicts`, `--default-off`, `--keep-legacy`, `--uninstall` (PowerShell: `-NoHook`, `-NoAgents`, `-NoCommand`, `-NoMod`, `-KeepConflicts`, `-DefaultOff`, `-KeepLegacy`, `-Uninstall`).

Then start a new session, or open `/hooks` once, so Claude Code loads the skill and hook.

**Claude Code cloud sessions (claude.ai/code).** Containers are rebuilt per session. Add this to the environment's setup script; it is pinned to a release tag for safety:

```bash
if git clone -q --depth 1 --branch v1.7.0 https://github.com/bahattab/Dynamic-Model-Selection /tmp/dms; then
  bash /tmp/dms/0-dynamic-model-selection/scripts/install.sh || echo "DMS install FAILED" >&2
else
  echo "DMS download FAILED" >&2
fi
```

**claude.ai / Claude apps.** Upload `0 - Dynamic Model Selection.skill` (attached to each [release](https://github.com/bahattab/Dynamic-Model-Selection/releases)) under Settings → Capabilities → Skills. It works there without the hook; trigger it with `DMS`.

**Other agents (Codex, Cursor, Gemini CLI, Copilot, …).** Copy `0-dynamic-model-selection/` into the agent's skills folder (for example `~/.agents/skills/`), or reference `SKILL.md` from the agent's `AGENTS.md`.

Full per-host steps and settings: [`0-dynamic-model-selection/SETUP.md`](0-dynamic-model-selection/SETUP.md).

## Verify

1. `DMS status` → mode, current model, route-log summary.
2. `thanks` → nothing added, no route line.
3. In a Sonnet conversation, a large architecture task → `🔀 Routed: Opus - …`.
4. `DMS off` → step 3 gives no route line. `DMS on` turns it back on.

## Routing rules

| Tier | Use when | Examples |
|---|---|---|
| **Haiku** `claude-haiku-5-5` | Read-only, answer is a fact/list/match, no judgment | find files, list TODOs, validate JSON |
| **Sonnet** `claude-sonnet-5-5` | Writes code, fixes bugs, tests, reviews within one component | fix a function, write tests, refactor |
| **Opus** `claude-opus-5-5` | Cross-component design, costly-to-reverse strategy, novel algorithms | system architecture, migration plans |

**Clear-win gate:** route only if the task needs a higher tier than the current model, or it is large, self-contained and read-heavy and a cheaper tier fits. Never route to the same tier, and never for quick questions or work that needs the conversation's context. Tie-breaks and worked examples: [`references/guide.md`](0-dynamic-model-selection/references/guide.md).

## Measuring savings

The hook and the model write one line per event to `~/.config/dms/routes.log` (`inject`, `skip`, `trigger`, `on`, `off`, `mod`, `route <tier> <subagent|session>`); the mod writes `mod.log` (`pass`, `switch`, `revert`, `recommend`, `judge`, `handpick`, `off`, `auto`, `keep`). Neither holds prompt text. `DMS status` summarises it with `scripts/dms-report.sh` (Windows: `scripts\dms-report.ps1`), including the share of prompts that were actually routed.

## Other routing mods

`model-selector` and `model-router` (from other Claude Code mod packs) decide the same things and would override DMS: Model Router changes even a subagent model DMS chose, and Model Selector runs a Sonnet call on every prompt. The installers disable both, only after the `dms` mod installed, and `--uninstall` turns them back on (`--keep-conflicts` to skip). `handoff` and `cache-clock` do not conflict. The `dms` mod adapts Model Router's judge prompt from claude-code-templates (MIT; see `plugins/dms/LICENSE-THIRD-PARTY.md`).

## Host support

| Host | Subagent on chosen model | New conversation on chosen model | Auto-routing hook |
|---|---|---|---|
| Claude Code / Claude desktop | Yes (Agent tool `model`; the mod keeps it) | Cloud sessions (`create_session`) | Yes; with the mod, the main model switches in code |
| claude.ai / Claude apps | Host-dependent | No | No |
| Other agents | If the host can set a task's model | Host-dependent | No |

## Repository layout

```
0-dynamic-model-selection/
├── SKILL.md              core rules (~1K tokens): classify, clear-win gate, route, log
├── references/guide.md   tie-breaks, examples, host adapters, Tier 1 pipeline categories
├── SETUP.md              per-host setup, settings, verification
├── VERSION, CHANGELOG.md
├── agents/openai.yaml    display metadata for agents that read it
├── commands/DMS.md       /DMS slash command for Claude Code
└── scripts/
    ├── install.sh, install.ps1        installers (+ uninstall)
    ├── dms-hook.sh, dms-hook.ps1      UserPromptSubmit hooks (same behaviour)
    └── dms-report.sh, dms-report.ps1  route-log summary
plugins/dms/                the Claude Code mod
├── hooks/register.ts       prompt.submit, turn.step, agent.spawn hooks
├── hooks/policy.ts         pure rules: pre-filter, judge prompt, clear-win gate, cache guard
├── tests/dms.test.ts       engine tests (claude plugin test)
└── LICENSE-THIRD-PARTY.md  MIT notice for the adapted Model Router logic
.claude-plugin/marketplace.json   marketplace for /plugin install
tests/
├── hook-cases.json       shared behaviour table for both hooks
├── run_hook_tests.py     runs the table against one hook
└── test_install.py       installer integration test
.github/workflows/
├── test.yml              Linux + Windows tests, shellcheck, PSScriptAnalyzer, version check
└── release.yml           publishes vX.Y.Z when VERSION changes (after Test passes)
```

## Testing

```bash
python3 tests/run_hook_tests.py bash 0-dynamic-model-selection/scripts/dms-hook.sh
```

```bash
python3 tests/test_install.py bash
```

```bash
claude plugin test plugins/dms
```

On Windows: `python tests\run_hook_tests.py powershell -NoProfile -ExecutionPolicy Bypass -File 0-dynamic-model-selection\scripts\dms-hook.ps1` and `python tests\test_install.py powershell`. CI runs all of these on every pull request.

## Limitations

- **Switching the conversation's model needs the mod.** Without it, DMS runs work on other models through subagents or new conversations and recommends `/model`. With it, the switch costs one cache re-read, which is why it only happens while the context is small.
- **The gate is followed by the model, not enforced by code.** The hook only filters short prompts and reminds the model of the rule; the route log shows whether routing stays rare.
- **Hook needs a reload** the first time (new session or `/hooks`).

## Versioning

[Semantic versioning](https://semver.org). The current version is in `0-dynamic-model-selection/VERSION`; releases are tagged `vX.Y.Z` and attach `0 - Dynamic Model Selection.skill`. History: [`CHANGELOG.md`](0-dynamic-model-selection/CHANGELOG.md).

**Releases are automatic.** The [`Release`](.github/workflows/release.yml) workflow runs when `VERSION` changes on `main`. It first runs the [`Test`](.github/workflows/test.yml) workflow, then creates tag `vX.Y.Z`, uses the matching `## X.Y.Z` section of `CHANGELOG.md` as the notes, and attaches the `.skill` package. To publish a new version:

1. Set the new number in `0-dynamic-model-selection/VERSION` and `metadata.version` in `SKILL.md`.
2. Add a `## X.Y.Z — YYYY-MM-DD` section at the top of `CHANGELOG.md`.
3. Merge to `main`.

A version that already has a tag is skipped, a missing changelog section stops the run, and a failing test blocks the release.

## Related skills

- **0 - Model Selector (MS skill):** cross-vendor and AI-product model selection with evaluated fallbacks. Use it for choosing models in general; use DMS for routing Claude work by task complexity at run time.
- **AMA (Advance Hybrid Agent Orchestrator):** when AMA orchestrates, it keeps scope, plan, Truth Mode and acceptance; DMS assigns the model for each delegated package.
