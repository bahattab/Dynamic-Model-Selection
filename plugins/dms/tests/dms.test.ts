import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

const USAGE = { input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 }

const ARCH = 'Design the event sourcing architecture for the orders and payments services and explain the tradeoffs'
const LIST = 'list every TypeScript file under src that imports the legacy auth module please'
const PLAIN = 'Please update the greeting text in the header component to say welcome back friend'

type World = {
  model?: string
  turns?: number
  tokens?: number
  judge?: string | null
  files?: Record<string, string>
}

/** Stands for the engine beneath the mod: env, files, session figures and the judge's reply. */
function world(on: On, w: World = {}) {
  const files: Record<string, string> = { ...(w.files ?? {}) }
  const judged: string[] = []
  mock.env(on, { HOME: '/home/t' })
  mock.clock(on, { now: Date.UTC(2026, 10, 14, 12, 0, 0) })
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => ({ value: files[e.path] ?? '' }))
  on('fs.write', (_, e) => {
    files[e.path] = String(e.text)
    return { value: undefined }
  })
  on('session.model', () => ({ value: w.model ?? 'claude-sonnet-5-5' }))
  on('session.turns', () => ({ value: w.turns ?? 1 }))
  on('session.usage', () => ({ value: { startedAt: 0, context: { tokens: w.tokens ?? 5_000, window: 1_000_000 }, rateLimits: [] } }))
  on('model.complete', (_, e) => {
    judged.push(String(e.prompt))
    return {
      value:
        w.judge === null
          ? ({ isAnswered: false, reason: 'empty-reply', usage: USAGE } as const)
          : ({ isAnswered: true, text: w.judge ?? '{"tier":"deep","confidence":0.9}', usage: USAGE } as const),
    }
  })
  const reached: { text: string; context?: readonly string[] }[] = []
  on('prompt.submit', (_, e) => {
    reached.push({ text: e.text, context: e.context })
    return { text: e.text, context: e.context }
  })
  const models: string[] = []
  on('turn.step', async function* (_, e) {
    models.push(e.model)
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null }
  })
  const spawned: (string | undefined)[] = []
  on('agent.spawn', (_, e) => {
    spawned.push(e.model)
    return { model: e.model ?? e.parentModel }
  })
  const log = () => files['/home/t/.config/dms/routes.log'] ?? ''
  return { files, judged, reached, models, spawned, log }
}

const submit = (text: string) => ({ text, wait: false, origin: { kind: 'composer' as const } })

async function step($: Engine, index = 0) {
  const s = $.turn.step({ turnId: 't1', index, model: 'claude-sonnet-5-5', messageCount: 3 })
  for await (const _ of s) {
    // drain
  }
  return s.result
}

test('a short prompt costs nothing: no judge call, nothing added', async ($, on) => {
  const w = world(on)
  await $.prompt.submit(submit('thanks, looks good'))
  expect(w.judged.length).toBe(0)
  expect(w.reached[0]?.context).toBeUndefined()
  expect(w.log()).toContain(' pass')
})

test('a long prompt with no tier hint costs nothing', async ($, on) => {
  const w = world(on)
  await $.prompt.submit(submit(PLAIN))
  expect(w.judged.length).toBe(0)
  expect(w.reached[0]?.context).toBeUndefined()
})

test('an opus-grade prompt in a sonnet chat switches the main model and says so', async ($, on) => {
  const w = world(on, { model: 'claude-sonnet-5-5', judge: '{"tier":"deep","confidence":0.9}' })
  await $.prompt.submit(submit(ARCH))
  expect(w.judged.length).toBe(1)
  expect(w.reached[0]?.context?.[0]).toContain('switched this conversation to Opus')
  await step($)
  expect(w.models).toEqual(['claude-opus-5-5'])
  expect(w.log()).toContain('switch deep main')
})

test('a hint for the tier already in use never calls the judge', async ($, on) => {
  const w = world(on, { model: 'claude-opus-5-5' })
  await $.prompt.submit(submit(ARCH))
  expect(w.judged.length).toBe(0)
})

test('a low-confidence judgement does not switch', async ($, on) => {
  const w = world(on, { judge: '{"tier":"deep","confidence":0.4}' })
  await $.prompt.submit(submit(ARCH))
  expect(w.reached[0]?.context).toBeUndefined()
  await step($)
  expect(w.models).toEqual(['claude-sonnet-5-5'])
})

test('a judge that does not answer leaves everything as it was', async ($, on) => {
  const w = world(on, { judge: null })
  await $.prompt.submit(submit(ARCH))
  expect(w.reached[0]?.context).toBeUndefined()
  expect(w.log()).toContain('judge none')
})

test('a large context only recommends, so the prompt cache is kept', async ($, on) => {
  const w = world(on, { tokens: 120_000, judge: '{"tier":"deep","confidence":0.9}' })
  await $.prompt.submit(submit(ARCH))
  expect(w.reached[0]?.context?.[0]).toContain('recommended - /model claude-opus-5-5')
  await step($)
  expect(w.models).toEqual(['claude-sonnet-5-5'])
  expect(w.log()).toContain('recommend deep main')
})

test('a downgrade needs the higher bar', async ($, on) => {
  const w = world(on, { model: 'claude-opus-5-5', judge: '{"tier":"fast","confidence":0.7}' })
  await $.prompt.submit(submit(LIST))
  expect(w.judged.length).toBe(1)
  expect(w.reached[0]?.context).toBeUndefined()
})

test('a confident downgrade from opus switches to haiku', async ($, on) => {
  const w = world(on, { model: 'claude-opus-5-5', judge: '{"tier":"fast","confidence":0.9}' })
  await $.prompt.submit(submit(LIST))
  await step($)
  expect(w.models).toEqual(['claude-haiku-5-5'])
})

test('DMS off (state file) turns automatic routing off', async ($, on) => {
  const w = world(on, { files: { '/home/t/.config/dms/disabled': '' } })
  await $.prompt.submit(submit(ARCH))
  expect(w.judged.length).toBe(0)
})

test('a DMS trigger prompt is left to the skill', async ($, on) => {
  const w = world(on)
  await $.prompt.submit(submit(`DMS ${ARCH}`))
  expect(w.judged.length).toBe(0)
})

test('a model the caller set on a subagent is never changed', async ($, on) => {
  const w = world(on, { judge: '{"tier":"fast","confidence":0.99}' })
  await $.agent.spawn({ prompt: LIST, description: 'scan', subagentType: 'general-purpose', model: 'opus', parentModel: 'claude-opus-5-5' } as never)
  expect(w.spawned).toEqual(['opus'])
  expect(w.judged.length).toBe(0)
  expect(w.log()).toContain('keep deep subagent')
})

test('an unset subagent of an opus parent can get cheaper', async ($, on) => {
  const w = world(on, { judge: '{"tier":"fast","confidence":0.9}' })
  await $.agent.spawn({ prompt: LIST, description: 'scan', subagentType: 'general-purpose', parentModel: 'claude-opus-5-5' } as never)
  expect(w.spawned).toEqual(['claude-haiku-5-5'])
  expect(w.log()).toContain('auto fast subagent')
})

test('an unset subagent of a sonnet parent costs no judge call', async ($, on) => {
  const w = world(on)
  await $.agent.spawn({ prompt: LIST, description: 'scan', subagentType: 'general-purpose', parentModel: 'claude-sonnet-5-5' } as never)
  expect(w.judged.length).toBe(0)
  expect(w.spawned).toEqual([undefined])
})

test('an unset subagent is never moved up', async ($, on) => {
  const w = world(on, { judge: '{"tier":"deep","confidence":0.99}' })
  await $.agent.spawn({ prompt: ARCH, description: 'plan', subagentType: 'general-purpose', parentModel: 'claude-opus-5-5' } as never)
  expect(w.spawned).toEqual([undefined])
})

test('the log never holds prompt text', async ($, on) => {
  const w = world(on, { judge: '{"tier":"deep","confidence":0.9}' })
  await $.prompt.submit(submit(ARCH))
  expect(w.log()).not.toContain('event sourcing')
})

test('picking a model by hand releases the switch', async ($, on) => {
  const state: World = { model: 'claude-sonnet-5-5', judge: '{"tier":"deep","confidence":0.9}' }
  const w = world(on, state)
  await $.prompt.submit(submit(ARCH))
  await step($)
  state.model = 'claude-haiku-5-5' // the person moved the app's picker
  await step($)
  expect(w.models).toEqual(['claude-opus-5-5', 'claude-sonnet-5-5'])
  expect(w.log()).toContain('handpick')
})

test('no second judge call inside the cooldown after a switch', async ($, on) => {
  const state: World = { model: 'claude-sonnet-5-5', turns: 1, judge: '{"tier":"deep","confidence":0.9}' }
  const w = world(on, state)
  await $.prompt.submit(submit(ARCH))
  state.turns = 2
  await $.prompt.submit(submit(LIST))
  expect(w.judged.length).toBe(1)
  expect(w.log()).toContain('pass cooldown')
})
