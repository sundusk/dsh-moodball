/**
 * dsh-moodball-status browser half — seats the MoodBall settings card in the
 * settings plugin section (a sibling of the built-in Shell / Agent loop /
 * Web search cards). There is no ball to render in the web UI: the desktop
 * app owns the visuals and consumes the host's `GET /api/moodball/status`.
 * @module @linxin666/dsh-moodball-status/client
 */

import type { ClientContext } from '@deepseek-ai/dsh-client-runtime/client'
// Type-only: pulls the locale plugin's Context merge (ctx.locale).
import type {} from '@deepseek-ai/dsh-client-locale/client'
// Type-only: pulls the settings-surface Context merge (ctx.settingsScope).
import type {} from '@deepseek-ai/dsh-client-ui-settings/client'
import type {} from '@deepseek-ai/dsh-client-ui-slots'
import { MoodBallSettingsCard, MoodBallSettingsCardController, type MoodBallSettings } from './MoodBallSettingsCard.tsx'
import { NS, en, zh } from './locales.ts'

/** Settings namespace the settings card edits (the host plugin registers it). */
const MOODBALL_SETTINGS_NS = 'moodball'

/** Required services. */
export const inject = ['slots', 'locale', 'settingsScope']

declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface SlotMap {
    /**
     * One plugin's configuration card inside the settings plugin section.
     * Type-only local copy of the slot the official SDK
     * (`dsh-client-ui-settings-plugins`) declares at runtime; kept here so
     * this plugin's typecheck stays self-contained. Registering here puts the
     * card on the same level as the built-in Shell / Agent loop / Web search
     * cards and the "Web UI 插件" family group.
     */
    'settings.plugin.item': { kind: 'list'; scope: 'root'; owner: SettingsPluginItemOwnerProps }
  }
}

/** Owner share of a plugin card (the settings section supplies nothing). */
export interface SettingsPluginItemOwnerProps {
  /** Marker field: card owner props are intentionally empty. */
  children?: never
}

/**
 * Client plugin body: register dictionaries and seat the settings card in the
 * settings plugin section.
 * @param ctx - client root context.
 */
export function apply(ctx: ClientContext): void {
  ctx.effect(() => ctx.locale.register(NS, { zh, en }), 'moodball: dictionaries')

  const settingsScope = ctx.settingsScope.bind<MoodBallSettings>({ namespace: MOODBALL_SETTINGS_NS })

  // Plugin configuration card: one staged form over the `moodball` settings
  // namespace, contributed to the settings plugin section at the top level
  // (a sibling of the built-in Shell / Agent loop / Web search cards).
  const card = new MoodBallSettingsCardController(settingsScope)
  ctx.slots.inject('settings.plugin.item', () => ctx.slots.register({
    name: 'settings.plugin.item',
    id: 'moodball-settings',
    order: 150,
    locale: NS,
    inject: () => card.inject(),
  }, MoodBallSettingsCard))
}
