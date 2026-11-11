# 0 - Dynamic Model Selection (DMS)

**Version 1.5.0** · Agent skill · Trigger: `DMS`

DMS routes each task to the Claude model its complexity calls for: **Haiku** for lookups and checks, **Sonnet** for code and bounded reasoning, **Opus** for architecture and hard-to-reverse decisions. It classifies the task, runs the work on that model (a subagent or a new conversation), escalates one tier when a result fails verification, and reports every route. You don't need to switch models with `/model`.

It is a standard `SKILL.md` skill, so any Markdown-capable agent can use it. Running work on another model depends on what the host supports; where that isn't possible, DMS gives a recommendation instead of claiming a switch.

---

## Contents

- [How it works](#how-it-works)
- [Commands](#commands)
- [Install](#install)
- [Verify](#verify)
- [Routing rules](#routing-rules)
- [Host support](#host-support)
- [Repository layout](#repository-layout)
- [Limitations](#limitations)
- [Versioning](#versioning)
- [Related skills](#related-skills)

---

## How it works

```
your prompt
   │
   ├─ UserPromptSubmit hook (Claude Code) adds: "DMS routing is ON"
   │
   ▼
Part A  Classify ── opus check → haiku check → default sonnet
   │
   ▼
Part B  Route
   ├─ quick question          → answer directly
   ├─ task fits this session  → subagent on the chosen model
   ├─ long independent work   → new conversation on the chosen model
   └─ mixed task              → split; one subagent + model per part
   │
   ▼
🔀 Routed: Sonnet - code fix in one module      ← reported before the result
```

**Part C** adds fixed categories (`default`, `deep-plan`, `quick-audit`, `visual`) for named pipeline roles. A tier gate decides when Part C applies.

## Commands

| You type | Effect |
|---|---|
| `DMS <task>` or `/DMS <task>` | Classify and route this task |
| `DMS` / `DMS status` | Show mode (on/off), routing tools, current model |
| `DMS on` | Route every prompt automatically |
| `DMS off` | Stop automatic routing (`DMS <task>` still works) |

Case-insensitive. Other names that load the skill: `0 - Dynamic Model Selection`, `$0-dynamic-model-selection`, and the legacy alias `model-selection`.

## Install

Clone or download, then run the installer from the skill folder.

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
powershell -ExecutionPolicy Bypass -File .\Dynamic-Model-Selection\0-dynamic-model-selection\scripts\install.ps1
```

The installer puts:

| Path | Purpose |
|---|---|
| `~/.claude/skills/0-dynamic-model-selection/` | Skill for Claude Code / Claude desktop |
| `~/.agents/skills/0-dynamic-model-selection/` | Shared skills folder for other agents |
| `~/.claude/commands/DMS.md` | `/DMS` slash command |
| `~/.claude/hooks/dms-hook.sh` (`.ps1` on Windows) | Automatic-routing hook |
| `~/.claude/settings.json` | `UserPromptSubmit` entry, merged with existing settings; backup at `settings.json.bak-dms` |

Options: `--no-hook`, `--no-agents`, `--no-command`, `--keep-legacy`, `--uninstall` (PowerShell: `-NoHook`, `-NoAgents`, `-NoCommand`, `-KeepLegacy`, `-Uninstall`).

Then start a new session, or open `/hooks` once, so Claude Code loads the skill and hook.

**Claude Code cloud sessions (claude.ai/code).** Containers are rebuilt per session. Add this to the environment's setup script so DMS is installed every time:

```bash
if git clone --depth 1 --branch v1.5.0 https://github.com/bahattab/Dynamic-Model-Selection /tmp/dms; then
  bash /tmp/dms/0-dynamic-model-selection/scripts/install.sh || true
fi
```

**claude.ai / Claude apps.** Upload `0 - Dynamic Model Selection.skill` from the [latest release](https://github.com/bahattab/Dynamic-Model-Selection/releases/latest) under Settings → Capabilities → Skills. The skill works there without the hook; trigger it with `DMS`.

**Other agents (Codex, Cursor, Gemini CLI, Copilot, …).** Copy `0-dynamic-model-selection/` into the agent's skills folder (for example `~/.agents/skills/`), or reference `SKILL.md` from the agent's `AGENTS.md`.

Full per-host steps: [`0-dynamic-model-selection/SETUP.md`](0-dynamic-model-selection/SETUP.md).

## Verify

1. `DMS` → a status line with the mode and current model.
2. `List the files in this folder` → `🔀 Routed: Haiku - …` before the result.
3. `DMS off`, then any task → no route line. `DMS on` turns it back on.

## Routing rules

| Tier | Use when | Examples |
|---|---|---|
| **Haiku** `claude-haiku-5-5` | Read-only, answer is a fact/list/match, no judgment | find files, list TODOs, validate JSON |
| **Sonnet** `claude-sonnet-5-5` | Writes code, fixes bugs, tests, reviews within one component | fix a function, write tests, refactor |
| **Opus** `claude-opus-5-5` | Cross-component design, costly-to-reverse strategy, novel algorithms | system architecture, migration plans |

Order: opus check → haiku check → sonnet by default. Start low; escalate one tier only when a result fails verification. Tie-breaks and worked examples are in `SKILL.md`.

## Host support

| Host | Subagent on chosen model | New conversation on chosen model | Auto-routing hook |
|---|---|---|---|
| Claude Code / Claude desktop | Yes (Agent tool `model`) | Cloud sessions (`create_session`) | Yes |
| claude.ai / Claude apps | Host-dependent | No | No |
| Other agents | If the host can set a task's model | Host-dependent | No |

## Repository layout

```
0-dynamic-model-selection/
├── SKILL.md            skill instructions (Parts A, B, C)
├── SETUP.md            per-host setup and verification
├── VERSION             1.5.0
├── CHANGELOG.md
├── agents/openai.yaml  display metadata for agents that read it
├── commands/DMS.md     /DMS slash command for Claude Code
└── scripts/
    ├── install.sh      macOS / Linux installer (+ --uninstall)
    ├── install.ps1     Windows installer (+ -Uninstall)
    ├── dms-hook.sh     UserPromptSubmit hook (bash)
    └── dms-hook.ps1    UserPromptSubmit hook (PowerShell)
```

## Limitations

- **The running conversation's own model doesn't change.** DMS runs work on other models through subagents or new conversations; only you can switch the current conversation (`/model`).
- **The routing conversation costs tokens too.** Run it on Sonnet to keep overhead low; it still sends hard work to Opus.
- **Hook needs a reload** the first time (new session or `/hooks`).
- **Windows scripts** (`install.ps1`, `dms-hook.ps1`) were written for Windows PowerShell 5.1+ but not executed in the release build environment; the bash scripts were tested.

## Versioning

[Semantic versioning](https://semver.org). Releases are tagged `vX.Y.Z`; each release attaches `0 - Dynamic Model Selection.skill`. History: [`CHANGELOG.md`](0-dynamic-model-selection/CHANGELOG.md).

## Related skills

- **0 - Model Selector (MS skill):** cross-vendor and AI-product model selection with evaluated fallbacks. Use it for choosing models in general; use DMS for routing Claude work by task complexity at run time.
- **AMA (Advance Hybrid Agent Orchestrator):** when AMA orchestrates, it keeps scope, plan, Truth Mode and acceptance; DMS assigns the model for each delegated package.
