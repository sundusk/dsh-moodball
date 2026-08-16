import { clientBundle } from './shared/tsdown.client.ts'

/**
 * Standalone tsdown config for the dsh-moodball-status plugin: the node half
 * builds from src/index.ts (ESM, cordis + dsh-settings external) and the
 * browser half builds the closure-factory artifact from src/client/index.ts,
 * with CSS modules inlined through the shared client preset.
 */
export default clientBundle('@linxin666/dsh-moodball-status', ['src/index.ts'], {
  libExternal: ['@deepseek-ai/dsh-settings'],
})
