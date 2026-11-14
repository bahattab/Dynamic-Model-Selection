/**
 * DMS mod for Claude Code: cost-first model routing in code, so the main model spends no
 * tokens on routing.
 *
 * - prompt.submit: a free gate (word count, then a wording hint; non-Latin prompts always go to
 *   the judge) decides whether a prompt is worth one small Haiku call. Only when the judge
 *   confidently names a different tier, and the context is small enough that losing the prompt
 *   cache is cheap for that direction, does DMS switch the main model. Otherwise it adds nothing,
 *   or one line recommending a switch. A switch lasts while the task does: the next substantial
 *   prompt without a hint for the held tier switches back.
 * - turn.step: puts the switched model on each main request, unless DMS is off or the person
 *   picked a model by hand (the picker changed, or a /model command ran).
 * - agent.spawn: a model the caller set is never changed, and neither is a subagent type that may
 *   define its own model. Only a general-purpose spawn with no model, under a deep-tier parent, may
 *   be moved to a cheaper tier by the judge.
 * - Decisions go to mod.log (never prompt text); the hook and the model write routes.log.
 */
import type { AgentSpawnInput, EngineInterface, PromptSubmitInput, Register, TurnStepInput } from 'claude-code'

import type { Hold, Memo } from '../types'
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
  needsJudgeAnyway,
  parseJudgement,
  rank,
  switchLimit,
  tierOf,
  wordCount,
  type Bars,
  type Judgement,
  type Tier,
  type Tiers,
} from './policy'

const HOLD = { plugin: 'dms', key: 'hold' } as const
const MEMO = { plugin: 'dms', key: 'memo' } as const
const NAME: Record<Tier, string> = { fast: 'Haiku', balanced: 'Sonnet', deep: 'Opus' }
const TAG = '[dms-mod]'
const LOG_MAX_LINES = 5000
/** Subagent types known to carry no model of their own; any other type keeps its own choice. */
const PLAIN_TYPES = new Set(['', 'general-purpose'])

interface Config {
  switchMain: boolean
  routeUnsetSubagents: boolean
  minWords: number
  maxSwitchContext: number
  maxSwitchContextDown: number
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
  if (!home) throw new Error('no home folder')
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

/** Appends one event line to mod.log; never throws, never logs prompt text. */
async function log($: EngineInterface, event: string): Promise<void> {
  try {
    const path = `${await stateDir($)}/mod.log`
    const stamp = new Date(await $.clock.now()).toISOString().replace(/\.\d{3}Z$/, 'Z')
    const old = (await $.fs.exists(path)) ? String(await $.fs.read(path)) : ''
    const lines = old.split('\n').filter(Boolean)
    lines.push(`${stamp} ${event}`)
    await $.fs.write(path, `${lines.slice(-LOG_MAX_LINES).join('\n')}\n`)
  } catch {
    // Logging is best effort.
  }
}

/** Tells the DMS command hook, for this session only, that the mod handles automatic routing. */
async function heartbeat($: EngineInterface): Promise<void> {
  try {
    const id = (await $.session.id()).replace(/[^A-Za-z0-9._-]/g, '_')
    await $.fs.write(`${await stateDir($)}/mod/${id}`, `${await $.clock.now()}\n`)
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
  return (await $.state.get(HOLD)).value ?? null
}

async function getMemo($: EngineInterface): Promise<Memo | null> {
  return (await $.state.get(MEMO)).value ?? null
}

async function release($: EngineInterface, why: string): Promise<void> {
  await $.state.set(HOLD, null)
  await log($, why)
}

function isTrigger(text: string): boolean {
  return /^\/?dms($|[\s:,.])/i.test(text.trim())
}

/** Prompts since `from`; a count that went backwards (/clear, compaction) reads as long ago. */
function since(now: number, from: number): number {
  return now >= from ? now - from : Number.MAX_SAFE_INTEGER
}

async function decideMain($: EngineInterface, e: PromptSubmitInput): Promise<PromptSubmitInput> {
  if (e.command) {
    // A /model command is a hand pick, even when it names the model DMS switched away from.
    if (e.command.name === 'model' && (await getHold($))) await release($, 'handpick')
    return e
  }
  if (e.isMeta || e.origin.kind !== 'composer' || isTrigger(e.text)) return e
  if (!(await isOn($))) {
    if (await getHold($)) await release($, 'off')
    return e
  }
  await heartbeat($)
  const say = (line: string): PromptSubmitInput => ({ ...e, context: [...(e.context ?? []), `${TAG} ${line}`] })
  if (wordCount(e.text) < cfg.minWords) {
    await log($, 'pass')
    return e
  }

  const pickerModel = await $.session.model()
  let hold = await getHold($)
  if (hold && pickerModel !== hold.base) {
    await release($, 'handpick')
    hold = null
  }
  const prompt = await $.session.turns()
  const hint = hintTier(e.text)

  // A held switch lasts while the task does: a substantial prompt with no hint for it ends it.
  if (hold && hint !== hold.tier && since(prompt, hold.atPrompt) >= 1) {
    const back = tierOf(hold.base, cfg.tiers)
    const tokens = (await $.session.usage()).context.tokens
    const upwards = back !== null && rank(back) > rank(hold.tier)
    if (upwards || (tokens !== undefined && cacheAllows(tokens, cfg.maxSwitchContextDown))) {
      const was = hold.tier
      await release($, `revert ${back ?? 'base'} main`)
      return say(`DMS switched this conversation back from ${NAME[was]} to the app's model (${hold.base}); the earlier task is done. Start your reply with: 🔀 Switched back: ${back ? NAME[back] : hold.base}`)
    }
  }

  const current = tierOf(hold?.model ?? pickerModel, cfg.tiers)
  const wanted = hint ?? (needsJudgeAnyway(e.text) ? 'any' : null)
  // The free pre-filter: no hint, an unranked model, or a hint for the tier in use costs nothing.
  if (!current || !wanted || wanted === current) {
    await log($, 'pass')
    return e
  }
  if (hold && since(prompt, hold.atPrompt) < cfg.cooldownPrompts) {
    await log($, 'pass cooldown')
    return e
  }
  const memo = await getMemo($)
  if (memo && memo.tier === wanted && since(prompt, memo.prompt) < cfg.cooldownPrompts) {
    await log($, 'pass judged')
    return e
  }
  const j = await judge($, e.text)
  if (j && wanted !== 'any') await $.state.set(MEMO, { prompt, tier: wanted })
  const target = j ? gate(current, j, cfg.bars) : null
  if (!target || !j) return e

  const conf = j.confidence?.toFixed(2) ?? 'n/a'
  const tokens = (await $.session.usage()).context.tokens
  const limit = switchLimit(current, target, cfg.maxSwitchContext, cfg.maxSwitchContextDown)
  // An unknown context size fails closed: no switch, only a recommendation.
  if (!cfg.switchMain || tokens === undefined || !cacheAllows(tokens, limit)) {
    await $.state.set(MEMO, { prompt, tier: target })
    await log($, `recommend ${target} main`)
    const why = cfg.switchMain ? `the context (${tokens ?? 'unknown'} tokens) is too large to switch cheaply` : 'automatic switching is off'
    return say(`DMS: this task fits ${NAME[target]} (judge confidence ${conf}), but ${why}. Answer it here and add one line: ✨ ${NAME[target]} recommended - /model ${cfg.tiers[target]}`)
  }
  await $.state.set(HOLD, { model: cfg.tiers[target], tier: target, base: pickerModel, atPrompt: prompt })
  await log($, `switch ${target} main`)
  return say(`DMS switched this conversation to ${NAME[target]} for this task (judge confidence ${conf}). Start your reply with: 🔀 Switched: ${NAME[target]} - <short reason>`)
}

/** The hold for this main request, after the hand-pick and on/off checks on the turn's first step. */
async function currentHold($: EngineInterface, e: TurnStepInput): Promise<Hold | null> {
  let hold = await getHold($)
  if (!hold || e.index !== 0) return hold
  await heartbeat($)
  const picker = await $.session.model()
  if (picker !== hold.base) {
    await release($, 'handpick')
    hold = null
  } else if (!(await isOn($))) {
    await release($, 'off')
    hold = null
  } else if (tierOf(picker, cfg.tiers) === hold.tier) {
    await $.state.set(HOLD, null)
    hold = null
  }
  return hold
}

async function decideSpawn($: EngineInterface, e: AgentSpawnInput): Promise<AgentSpawnInput> {
  if (e.fork || e.resume || e.workflow) return e
  if (e.model && e.model !== 'inherit') {
    await log($, `keep ${tierOf(e.model, cfg.tiers) ?? 'other'} subagent`)
    return e
  }
  // A typed subagent may define its own model; undefined lets that model decide, so leave it.
  if (!PLAIN_TYPES.has(e.subagentType ?? '')) return e
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
    maxSwitchContextDown: num('maxSwitchContextDown', 150_000),
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
    const hold = await currentHold($, e).catch(() => null)
    if (!hold) return yield* next(e)
    // A top effort level may not exist on a cheaper model: move down with at most `high`.
    const effort = hold.tier === 'fast' && (e.effort === 'xhigh' || e.effort === 'max') ? 'high' : e.effort
    return yield* next({ ...e, model: hold.model, effort })
  })

  // Subagents: an explicit model always wins; an unset one may only get cheaper, from a deep parent.
  on('agent.spawn', async ($, e, next) => next(await decideSpawn($, e).catch(() => e)))
}
