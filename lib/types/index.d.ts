/**
 * dsh-moodball-status host half — a pure host plugin (no browser UI, no
 * settings namespace) that tracks agent activity and serves the current mood
 * over a same-origin JSON route for the MoodBall macOS desktop app. Install
 * via `dsh plugin --profile web add github:sundusk/dsh-moodball`.
 * @module @linxin666/dsh-moodball-status
 */
import { Context } from '@deepseek-ai/cordis';
/** Stable cordis plugin name (matches cordis.patch.yml insert id). */
export declare const name = "moodball";
/** Services required before the status surface can mount. */
export declare const inject: string[];
/** The mood the desktop app renders (same vocabulary as the web water ball). */
export type MoodballMood = 'idle' | 'waiting' | 'jumping' | 'done' | 'failed' | 'stopped' | 'waving' | 'authorizing' | 'questioning';
/**
 * Register the MoodBall status surface: fold the agent session stream into a
 * mood and serve it over GET /api/moodball/status. The route is always live
 * while the plugin is loaded — there is no settings namespace to toggle.
 * @param ctx - host root context.
 */
export declare function apply(ctx: Context): void;
