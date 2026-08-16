/**
 * The MoodBall settings card: the enable master switch, bound to the `moodball`
 * settings namespace the host plugin registers. Flipping it off removes the
 * host status route, so the desktop app shows 插件已关闭.
 */

import type { InjectFace, PropsLocale, PropsRuntime } from '@deepseek-ai/dsh-client-ui-slots'
import type { SettingsScope, SnapshotStore } from '@deepseek-ai/dsh-client-runtime/client'
import { PluginSettingsCard, BooleanField } from './PluginSettingsCard.tsx'
import { CardForm, booleanField, type CardActions, type CardShell, type FieldState as CardFieldState } from './settings-form.ts'

/** The moodball settings fields this card edits. */
export interface MoodBallSettings {
  /** Master switch for the status API. */
  enabled?: boolean
}

/** What the MoodBall settings card renders. */
export interface MoodBallSettingsCardState extends CardShell {
  /** Plugin master switch. */
  enabled: CardFieldState
}

/** The registration-side face the card's slot entry injects. */
export interface MoodBallSettingsCardFace extends CardActions {
  hooks: {
    /** Card snapshot bound by the renderer as useMoodBallSettingsCard. */
    moodBallSettingsCard: SnapshotStore<MoodBallSettingsCardState>
  }
}

/** Bridges the `moodball` scope onto the card's staged form. */
export class MoodBallSettingsCardController {
  private readonly form: CardForm<MoodBallSettings>
  private readonly store: SnapshotStore<MoodBallSettingsCardState>

  /** @param scope - the bound settings scope for the `moodball` namespace. */
  constructor(scope: SettingsScope<MoodBallSettings>) {
    this.form = new CardForm(scope, [
      booleanField('enabled'),
    ])
    this.store = this.form.bind(() => this.projection())
  }

  private projection(): MoodBallSettingsCardState {
    return {
      ...this.form.shell(),
      enabled: this.form.field('enabled'),
    }
  }

  /**
   * Build the face the card's slot registration injects.
   * @returns the card's snapshot and its form actions.
   */
  inject(): MoodBallSettingsCardFace {
    return { hooks: { moodBallSettingsCard: this.store }, ...this.form.actions() }
  }
}

/** Props the renderer binds for the MoodBall settings card. */
export type MoodBallSettingsCardProps =
  PropsRuntime<'settings.plugin.item'>
  & PropsLocale<'moodball'>
  & InjectFace<MoodBallSettingsCardFace>

/**
 * Render the MoodBall settings card.
 * @param props - locale copy, the card snapshot, and its form actions.
 * @returns the card.
 */
export function MoodBallSettingsCard(props: MoodBallSettingsCardProps) {
  const { t } = props
  const state = props.useMoodBallSettingsCard(snapshot => snapshot)
  const disabled = !state.writable
  const fieldProps = {
    overriddenLabel: t('settings.overridden'),
    resetLabel: t('settings.reset'),
    invalidLabel: t('settings.invalidNumber'),
    disabled,
  }
  return (
    <PluginSettingsCard
      t={t}
      titleKey="settings.title"
      descriptionKey="settings.description"
      state={state}
      onSave={props.save}
      onDiscard={props.discard}
    >
      <BooleanField
        id="settings-moodball-enabled"
        label={t('settings.enabled')}
        hint={t('settings.enabledHint')}
        inheritLabel={t('settings.inherit')}
        onLabel={t('settings.on')}
        offLabel={t('settings.off')}
        {...fieldProps}
        {...state.enabled}
        onEdit={(text) => { props.edit('enabled', text) }}
        onReset={() => { props.resetField('enabled') }}
      />
    </PluginSettingsCard>
  )
}
