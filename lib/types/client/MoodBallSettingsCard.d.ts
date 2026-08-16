/**
 * The MoodBall settings card: the enable master switch, bound to the `moodball`
 * settings namespace the host plugin registers. Flipping it off removes the
 * host status route, so the desktop app shows 插件已关闭.
 */
import type { InjectFace, PropsLocale, PropsRuntime } from '@deepseek-ai/dsh-client-ui-slots';
import type { SettingsScope, SnapshotStore } from '@deepseek-ai/dsh-client-runtime/client';
import { type CardActions, type CardShell, type FieldState as CardFieldState } from './settings-form.ts';
/** The moodball settings fields this card edits. */
export interface MoodBallSettings {
    /** Master switch for the status API. */
    enabled?: boolean;
}
/** What the MoodBall settings card renders. */
export interface MoodBallSettingsCardState extends CardShell {
    /** Plugin master switch. */
    enabled: CardFieldState;
}
/** The registration-side face the card's slot entry injects. */
export interface MoodBallSettingsCardFace extends CardActions {
    hooks: {
        /** Card snapshot bound by the renderer as useMoodBallSettingsCard. */
        moodBallSettingsCard: SnapshotStore<MoodBallSettingsCardState>;
    };
}
/** Bridges the `moodball` scope onto the card's staged form. */
export declare class MoodBallSettingsCardController {
    private readonly form;
    private readonly store;
    /** @param scope - the bound settings scope for the `moodball` namespace. */
    constructor(scope: SettingsScope<MoodBallSettings>);
    private projection;
    /**
     * Build the face the card's slot registration injects.
     * @returns the card's snapshot and its form actions.
     */
    inject(): MoodBallSettingsCardFace;
}
/** Props the renderer binds for the MoodBall settings card. */
export type MoodBallSettingsCardProps = PropsRuntime<'settings.plugin.item'> & PropsLocale<'moodball'> & InjectFace<MoodBallSettingsCardFace>;
/**
 * Render the MoodBall settings card.
 * @param props - locale copy, the card snapshot, and its form actions.
 * @returns the card.
 */
export declare function MoodBallSettingsCard(props: MoodBallSettingsCardProps): import("react").JSX.Element;
