export type Tier = 'fast' | 'balanced' | 'deep'

/** A main-conversation switch DMS made: kept on every main request until the person picks a model by hand. */
export type Hold = {
  /** The full model id DMS puts on each main request. */
  model: string
  tier: Tier
  /** The model the app's picker named when DMS switched; a different one later means a hand pick. */
  base: string
  /** The prompt number (`$.session.turns()`) the switch was made at. */
  atPrompt: number
}

declare module 'claude-code' {
  interface PluginState {
    dms: { hold: Hold | null }
  }
}
