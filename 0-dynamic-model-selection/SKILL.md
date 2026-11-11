---
name: 0-dynamic-model-selection
description: |
  Trigger on "DMS" (case-insensitive), "/DMS", "0 - Dynamic Model Selection",
  $0-dynamic-model-selection, or the legacy alias "model-selection". Routes each task to the
  Claude model its complexity calls for (haiku, sonnet, or opus): classifies the task, runs it
  on a subagent or a new conversation with that model, escalates on failed verification, and
  reports every route. Use when routing tasks, choosing subagent models, turning automatic
  routing on or off ("DMS on" / "DMS off"), or optimizing cost/quality tradeoffs. Portable to
  any Markdown-capable agent; switching models depends on host support.
metadata:
  version: 1.5.0
  display-name: 0 - Dynamic Model Selection
  trigger: DMS
  legacy-aliases: model-selection, sk-dynamic-routing
---
# 0 - Dynamic Model Selection (DMS)

DMS picks the right model for each task by complexity and runs the work on it.

- **Part A — Classify:** decide haiku, sonnet, or opus for any task. Works in every agent.
- **Part B — Route:** run the task on that model with the tools the host provides.
- **Part C — Pipeline categories:** fixed categories for named pipeline roles (Tier 1 only).

Before first use, read `SETUP.md` in this folder and complete any setup it lists for the current host.

## Commands

| User types | Action |
|---|---|
| `DMS` or `/DMS` + a task | Classify the task and route it (Part B). |
| `DMS` alone | Report the current mode (auto-routing on/off), the host's routing tools, and the current conversation's model. |
| `DMS on` | Turn automatic routing on for every prompt (needs the hook from `SETUP.md`). |
| `DMS off` | Turn automatic routing off. `DMS <task>` still routes on request. |
| `DMS status` | Same as `DMS` alone. |

Matching is case-insensitive.

## Truthfulness rules

- Report a model switch only after it is verified. Never claim a switch, a subagent, or a new conversation that did not happen.
- If the host cannot run work on another model, say so and give the recommendation instead.
- Escalation and fallback events are always reported, never silent.

---

## Part A — Classify

### Model tiers

| Tier | Full ID | Alias |
|---|---|---|
| Haiku | `claude-haiku-5-5` | `haiku` |
| Sonnet | `claude-sonnet-5-5` | `sonnet` |
| Opus | `claude-opus-5-5` | `opus` |

Use the full ID in agent files and session APIs; use the alias where a tool takes only aliases. Never write a partial name such as `sonnet-5-5`. If the host offers newer IDs, use the host's current IDs for the same three tiers.

#### Haiku — fast and efficient
**Use haiku when all of these hold:**
- The task is read-only (no files are created or modified).
- The answer is a fact, a list, a match, or a yes/no check.
- No judgment about tradeoffs or design is needed.

**Typical tasks:** lookups, searches, pattern matching across files, listing files or contents, basic formatting or transformation, summarizing without deep analysis, syntax or schema validation.

**Indicators:** "find", "search", "list", "scan", "check", "what is", "where is", "show me", short direct questions, file/directory operations.

#### Sonnet — balanced and capable
**Use sonnet when the task involves:**
- Writing, modifying, or refactoring code
- Implementing or extending features
- Bug investigation and fixing
- Test writing
- Code review, or analysis that stays within one component
- Documentation that needs context
- Multi-step reasoning with a bounded set of tradeoffs

**Indicators:** "implement", "create", "build", "write", "fix", "debug", "investigate", "refactor", "improve", "optimize", "review", "analyze", code snippets or file references, feature descriptions.

#### Opus — deep and complex
**Use opus when the task involves:**
- Architectural design across several components or services
- Strategic planning where a wrong choice is expensive to reverse
- Novel algorithm development
- Decisions with significant, system-wide tradeoffs
- Problems that need several expert perspectives reconciled
- Work where correctness is critical and the reasoning is complex

**Indicators:** "architect", "design the … system", "strategy", "tradeoffs", "novel", "system-wide", "multiple interacting components", abstract reasoning required.

### Decision algorithm

Apply in order; stop at the first match.

1. **Opus check.** The task requires a decision that spans multiple components or is costly to reverse → **opus**.
2. **Haiku check.** The task is read-only *and* needs no judgment → **haiku**.
3. **Default** → **sonnet**.
4. **Escalate on evidence.** Start at the lowest tier that fits. If the result is wrong, incomplete, or fails verification, re-run one tier up. Do not start at opus "to be safe".

### Tie-break rules

| Situation | Choose | Reason |
|---|---|---|
| Lookup plus any write (edit, create, commit) | sonnet | Writes need code-level care. |
| Lookup plus analysis | sonnet | The analysis decides the model; split the lookup into a haiku subagent if it can run in parallel. |
| "Plan" with a checklist or single-file scope | sonnet | Bounded planning is not architecture. |
| "Design" for a UI component, copy, or one module | sonnet | Opus is for cross-component design. |
| "Design" for system architecture or service boundaries | opus | Cross-component, hard to reverse. |
| Haiku result fails verification | sonnet, then opus | Escalate on evidence only. |

### Worked examples

| Prompt | Model | Reason |
|---|---|---|
| "List every TODO comment under `src/`" | haiku | Read-only listing. |
| "Is this JSON valid against the order schema?" | haiku | Validation, no judgment. |
| "Fix the null check in `parseConfig()`" | sonnet | Code change in one function. |
| "Rename `x` to `userId` across this file" | sonnet | Write action. |
| "Write unit tests for the billing module" | sonnet | Test writing. |
| "Review this PR for race conditions" | sonnet | One component; escalate to opus if it changes concurrency design across services. |
| "Design the event-sourcing architecture for orders and payments" | opus | Cross-service, hard to reverse. |
| "Plan the migration from monolith to services" | opus | Strategic and system-wide. |

### Cost-quality tradeoff

| Model | Speed | Cost | Quality |
|-------|-------|------|---------|
| Haiku | ★★★★★ | ★★★★★ | ★★★ |
| Sonnet | ★★★ | ★★★ | ★★★★ |
| Opus | ★★ | ★ | ★★★★★ |

When in doubt, prefer sonnet.

---

## Part B — Route

### Routing by task size

1. **Quick question, clarification, or a reply needing no tools** → answer directly. Routing costs more than it saves.
2. **Task that fits in this conversation** → run it on a subagent with the chosen model; relay the result.
3. **Long, independent work** → start a new conversation on the chosen model.
4. **Mixed task** → split it; each part gets its own subagent and model (e.g. haiku for the search, sonnet for the fix, opus for the design decision).
5. **Host has no way to run another model** → do the work in the current conversation and report the recommendation.

### Report format

Before the result, one line per routed part:

```
🔀 Routed: <Model> - <reason>
```

Recommendation only (no switch possible): `✨ <Model> recommended - <reason>`.
New conversation (verified): `🔀 Switched: new conversation <id> on <model> - <reason>`.

### Host adapters

Use the first adapter whose tools the host actually has.

**Claude Code / Claude desktop (Code sessions)**
- Subagents: call the Agent tool with `model` set to the alias (`haiku`, `sonnet`, `opus`). Always pass it; an omitted model inherits the conversation's model. Forked subagents ignore `model`; spawn a fresh subagent when a different model is needed.
- Agent files: set frontmatter `model:` to the full ID and add `# model-category: <category>`.
- New conversations (cloud sessions): `create_session` with `model` = full ID, a stand-alone `prompt`, and a `title`. Verify with `get_session` → `session_context.model` before reporting the switch.
- Current conversation: only the user can change it (`/model <id>` or the model picker). Report a switch only after the host confirms it.
- Automatic routing: the `UserPromptSubmit` hook in `scripts/` injects the routing instruction on every prompt (see `SETUP.md`).

**Other agents (Codex, Cursor, Gemini CLI, Copilot, any Markdown-capable agent)**
- If the host can start a subagent or task with a chosen model, pass the tier's model there.
- If the host maps tiers to its own models, use its fast / balanced / deep equivalents and state the mapping.
- Otherwise, apply Part A, do the work, and report `✨ <Model> recommended`.

### Router cost

The conversation that routes also consumes tokens for classification and relaying. To keep that low, run the routing conversation on sonnet; it still routes opus work to opus subagents.

---

## Part C — Pipeline Categories (Tier 1)

### Tier gate (run first)

Resolve the tier from the first source that answers:

1. **Explicit pipeline profile.** If the caller supplies `platform_profile.tier`: `tier_1` → continue; any other value (`tier_1b`, `tier_1c`, `tier_1d`, `tier_2`) → stop and resolve models through `platform_profile.model_tiers` only.
2. **Runtime detection.** With no profile, treat the session as `tier_1` when `CLAUDECODE=1` is set and the subagent tool accepts a `model` parameter.
3. **Neither** → stop; Part C has no effect. Use Parts A and B.

State the source, e.g. `Tier gate: tier_1 (runtime: CLAUDECODE=1, Agent tool with model)`.

Tier-agnostic orchestrators (`creating-a-pipeline`, `pipeline-architect-protocol`, `sk-platform-dispatch`) must run this gate themselves before applying Part C.

### Category mappings

All routes are Claude models, because Claude Code dispatches subagents to Claude models only.

| Category | Primary | Fallback | Use case |
| :--- | :--- | :--- | :--- |
| `default` | `claude-sonnet-5-5` | *None* | Implementation, general tasks, task execution. |
| `deep-plan` | `claude-opus-5-5` | `claude-sonnet-5-5` | High-stakes architectural planning (e.g. `pipeline-architect`). |
| `quick-audit` | `claude-haiku-5-5` | `claude-sonnet-5-5` | Fast, broad pattern matching and codebase grepping. |
| `visual` | `claude-sonnet-5-5` | `claude-opus-5-5` | Screenshots, UI images, diagrams. Escalate to opus when the diagram drives an architectural decision. |

### Category protocol

1. **Evaluate intent.** Identify the pipeline role.
2. **Assign category.** Planning/architecture → `deep-plan`; read-only utility → `quick-audit`; screenshots/diagrams → `visual`; everything else → `default`.
3. **Dispatch** per the host adapter in Part B.
4. **Fallback** only when the primary is unavailable or rate-limited. A quality concern is not a fallback trigger; use Part A escalation. Record which model served the stage.

### Invariants

- NEVER override `pipeline-task-executor` or `pipeline-spec-reviewer`; they stay on `claude-sonnet-5-5` (`default`).
- NEVER route to a model outside the category table.
- `MODEL_SELECTION: DYNAMIC_DEFAULT_SONNET`: on Tier 1, `default` equals `platform_profile.model_tiers.fast` (`claude-sonnet-5-5`).
- NEVER apply Part C without passing the tier gate.
- Fallback use MUST be recorded.

---

## Related skills

- **0 - Model Selector (MS skill):** choosing models across vendors or for AI product features, with evaluated fallback policies. Use MS for that; use DMS for routing Claude work by task complexity at run time.
- **AMA:** when AMA orchestrates, AMA keeps scope, plan, Truth Mode, and acceptance; DMS only assigns the model for each delegated package.
