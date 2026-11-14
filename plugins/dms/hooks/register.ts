/**
 * DMS mod for Claude Code: cost-first model routing in code, so the main model spends no
 * tokens on routing.
 *
 * - prompt.submit: a free gate (word count, then a wording hint) decides whether a prompt is
 *   worth one small Haiku call. Only when the judge confidently names a different tier, and the
 *   context is small enough that losing the prompt cache is cheap, does DMS switch the main
 *   model. Otherwise it adds nothing, or one line recommending a switch.
 * - turn.step: puts the switched model on each main request until the person picks by hand.
 * - agent.spawn: a model the caller set is never changed. A spawn that names no model inherits
 *   the parent's; only when the parent runs on the deep tier does a judge look for a cheaper one.
 * - Every decision is one line in routes.log (never prompt text), the same file the DMS hook and
 *   the report scripts use.
 */
import type { AgentSpawnInput, EngineInterface, PromptSubmitInput, Register } from 'claude-code'

import type { Hold } from '../types'
import {
  DEFAULT_BARS,
  DEFAULT_TIERS,
  JUDGE_MAX_TOKENS,
  JUDGE_MODEL,
  JUDGE_SYSTEM,
  cacheAllows,
  gate,
  hintTier,
  judgePrompt,
  parseJudgement,
  tierOf,
  wordCount,
  type Bars,
  type Judgement,
  type Tier,
  type Tiers,
} from './policy'

const HOLD = { plugin: 'dms', key: 'hold' } as const
const NAME: Record<Tier, string> = { fast: 'Haiku', balanced: 'Sonnet', deep: 'Opus' }
const LOG_MAX_LINES = 5000

interface Config {
  switchMain: boolean
  routeUnsetSubagents: boolean
  minWords: number
  maxSwitchContext: number
  cooldownPrompts: number
  timeoutMs: number
  bars: Bars
  tiers: Tiers
}

let cfg: Config

async function stateDir($: EngineInterface): Promise<string> {
  const own = await $.env.get('DMS_STATE_DIR')
  if (own) return own.replace(/\\/g, '/').replace(/\/$/, '')
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE')) || ''
  return `${home.replace(/\\/g, '/').replace(/\/$/, '')}/.config/dms`
}

/** Automatic routing on or off: the `DMS on` / `DMS off` files win over DMS_DEFAULT (default on). */
async function isOn($: EngineInterface): Promise<boolean> {
  const dir = await stateDir($)
  if (await $.fs.exists(`${dir}/disabled`).catch(() => false)) return false
  if (await $.fs.exists(`${dir}/enabled`).catch(() => false)) return true
  const d = String((await $.env.get('DMS_DEFAULT')) ?? 'on').toLowerCase()
  return !['off', '0', 'false', 'no'].includes(d)
}

/** Appends one event line to routes.log; never throws, never logs prompt text. */
async function log($: EngineInterface, event: string): Promise<void> {
  try {
    const dir = await stateDir($)
    const path = `${dir}/routes.log`
    const stamp = new Date(await $.clock.now()).toISOString().replace(/\.\d{3}Z$/, 'Z')
    const old = (await $.fs.exists(path)) ? String(await $.fs.read(path)) : ''
    const lines = old.split('\n').filter(Boolean)
    lines.push(`${stamp} ${event}`)
    await $.fs.write(path, `${lines.slice(-LOG_MAX_LINES).join('\n')}\n`)
  } catch {
    // Logging is best effort.
  }
}

/** Tells the DMS command hook that the mod handles automatic routing, so it stays silent. */
async function heartbeat($: EngineInterface): Promise<void> {
  try {
    const dir = await stateDir($)
    await $.fs.write(`${dir}/mod-active`, `${await $.clock.now()}\n`)
  } catch {
    // Without the heartbeat the hook only adds its one-line reminder.
  }
}

async function judge($: EngineInterface, task: string, description?: string): Promise<Judgement | null> {
  try {
    const r = await $.model.complete({
      model: JUDGE_MODEL,
      system: JUDGE_SYSTEM,
      prompt: judgePrompt(task, description),
      maxTokens: JUDGE_MAX_TOKENS,
      effort: 'low',
      timeoutMs: cfg.timeoutMs,
    })
    if (!r.isAnswered) {
      await log($, 'judge none')
      return null
    }
    const j = parseJudgement(r.text)
    await log($, j ? `judge ${j.tier} ${j.confidence ?? 'n/a'}` : 'judge unreadable')
    return j
  } catch {
    await log($, 'judge error')
    return null
  }
}

async function getHold($: EngineInterface): Promise<Hold | null> {
  const { value } = await $.state.get(HOLD)
  return value ?? null
}

function isTrigger(text: string): boolean {
  return /^\/?dms($|[\s:,.])/i.test(text.trim())
}

async function decideMain($: EngineInterface, e: PromptSubmitInput): Promise<PromptSubmitInput> {
  if (e.command || e.isMeta || e.origin.kind !== 'composer' || isTrigger(e.text)) return e
  if (!(await isOn($))) return e
  await heartbeat($)
  if (wordCount(e.text) < cfg.minWords) {
    await log($, 'pass')
    return e
  }
  const hold = await getHold($)
  const pickerModel = await $.session.model()
  const current = tierOf(hold?.model ?? pickerModel, cfg.tiers)
  const hint = hintTier(e.text)
  // The free pre-filter: no hint, an unranked model, or a hint for the tier in use costs nothing.
  if (!current || !hint || hint === current) {
    await log($, 'pass')
    return e
  }
  const prompt = await $.session.turns()
  if (hold && prompt - hold.atPrompt < cfg.cooldownPrompts) {
    await log($, 'pass cooldown')
    return e
  }
  const j = await judge($, e.text)
  const target = j ? gate(current, j, cfg.bars) : null
  if (!target || !j) return e

  const conf = j.confidence?.toFixed(2) ?? 'n/a'
  const tokens = (await $.session.usage()).context.tokens
  if (!cfg.switchMain || !cacheAllows(tokens, cfg.maxSwitchContext)) {
    await log($, `recommend ${target} main`)
    const why = cfg.switchMain ? `the context (${tokens ?? '?'} tokens) is too large to switch cheaply` : 'automatic switching is off'
    const line = `DMS: this task fits ${NAME[target]} (judge confidence ${conf}), but ${why}. Answer it here and tell the user once: ✨ ${NAME[target]} recommended - /model ${cfg.tiers[target]}`
    return { ...e, context: [...(e.context ?? []), line] }
  }
  await $.state.set(HOLD, { model: cfg.tiers[target], tier: target, base: pickerModel, atPrompt: prompt })
  await log($, `switch ${target} main`)
  const line = `DMS switched this conversation to ${NAME[target]} for this task (judge confidence ${conf}). Start your reply with: 🔀 Switched: ${NAME[target]} - <short reason>`
  return { ...e, context: [...(e.context ?? []), line] }
}

async function currentHold($: EngineInterface, index: number): Promise<Hold | null> {
  let hold = await getHold($)
  if (hold && index === 0) {
    const picker = await $.session.model()
    if (picker !== hold.base) {
      await $.state.set(HOLD, null)
      await log($, 'handpick')
      hold = null
    } else if (tierOf(picker, cfg.tiers) === hold.tier) {
      await $.state.set(HOLD, null)
      hold = null
    }
  }
  return hold
}

async function decideSpawn($: EngineInterface, e: AgentSpawnInput): Promise<AgentSpawnInput> {
  if (e.fork || e.resume || e.workflow) return e
  if (e.model && e.model !== 'inherit') {
    await log($, `keep ${tierOf(e.model, cfg.tiers) ?? e.model} subagent`)
    return e
  }
  const parent = tierOf(e.parentModel, cfg.tiers)
  if (!cfg.routeUnsetSubagents || parent !== 'deep' || !(await isOn($))) return e
  const j = await judge($, e.prompt, e.description)
  const target = j ? gate(parent, j, cfg.bars, false) : null
  if (!target) return e
  await log($, `auto ${target} subagent`)
  return { ...e, model: cfg.tiers[target] }
}

export const register: Register = (on, options) => {
  const num = (k: string, d: number) => (typeof options[k] === 'number' ? (options[k] as number) : d)
  const flag = (k: string, d: boolean) => (typeof options[k] === 'boolean' ? (options[k] as boolean) : d)
  const str = (k: string, d: string) => (typeof options[k] === 'string' && options[k] ? (options[k] as string) : d)
  cfg = {
    switchMain: flag('switchMain', true),
    routeUnsetSubagents: flag('routeUnsetSubagents', true),
    minWords: num('minWords', 12),
    maxSwitchContext: num('maxSwitchContext', 40_000),
    cooldownPrompts: num('cooldownPrompts', 3),
    timeoutMs: num('timeoutMs', 6_000),
    bars: { up: num('upConfidence', DEFAULT_BARS.up), down: num('downConfidence', DEFAULT_BARS.down) },
    tiers: {
      fast: str('fastModel', DEFAULT_TIERS.fast),
      balanced: str('balancedModel', DEFAULT_TIERS.balanced),
      deep: str('deepModel', DEFAULT_TIERS.deep),
    },
  }

  on('session.start', async ($, e, next) => {
    const r = await next(e)
    await heartbeat($)
    return r
  })

  // The main conversation: decide once per prompt, before the turn starts.
  // Any error lets the prompt through unchanged; next is called exactly once.
  on('prompt.submit', async ($, e, next) => next(await decideMain($, e).catch(() => e)))

  // Every main request: put the held model on, unless the person picked a model by hand.
  on('turn.step', async function* ($, e, next) {
    if (e.agentId !== undefined) return yield* next(e)
    const hold = await currentHold($, e.index).catch(() => null)
    if (!hold) return yield* next(e)
    return yield* next({ ...e, model: hold.model })
  })

  // Subagents: an explicit model always wins; an unset one may only get cheaper, from a deep parent.
  on('agent.spawn', async ($, e, next) => next(await decideSpawn($, e).catch(() => e)))

}
