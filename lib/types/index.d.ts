/**
 * dsh-moodball-status host half — tracks agent activity and serves the current
 * mood over a same-origin JSON route for the MoodBall macOS desktop app. A
 * pure host plugin (no browser UI); the `moodball` settings namespace backs
 * the Web settings card (enabled, default true). Install via
 * `dsh plugin --profile web add github:sundusk/dsh-moodball`.
 * @module @linxin666/dsh-moodball-status
 */
import { Context } from '@deepseek-ai/cordis';
import z from 'schemastery';
/** Stable cordis plugin name (matches cordis.patch.yml insert id). */
export declare const name = "moodball";
/** Services required before the status surface can mount. */
export declare const inject: string[];
/** Settings namespace of the moodball capability (the browser card edits it). */
export declare const MOODBALL_SETTINGS_NAMESPACE = "moodball";
/** Settings section schema: one master switch, on by default. */
export interface MoodballSettingsSection {
    /** Master switch: off removes the status route (desktop ball shows 插件已关闭). */
    enabled?: boolean;
}
/** Settings section schema. */
export declare const MOODBALL_SETTINGS_SCHEMA: z<Schemastery.ObjectS<{
    enabled: z<boolean, boolean>;
}>, Schemastery.ObjectT<{
    enabled: z<boolean, boolean>;
}>>;
/** The mood the desktop app renders (same vocabulary as the web water ball). */
export type MoodballMood = 'idle' | 'waiting' | 'jumping' | 'done' | 'failed' | 'stopped' | 'waving' | 'authorizing' | 'questioning';
/**
 * Register the MoodBall status surface: fold the agent session stream into a
 * mood and serve it over GET /api/moodball/status. The route is live while the
 * `moodball` settings namespace is enabled; toggling it off removes the route
 * until re-enabled.
 * @param ctx - host root context.
 */
export declare function apply(ctx: Context): void;
