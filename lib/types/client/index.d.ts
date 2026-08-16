/**
 * dsh-moodball-status browser half — seats the MoodBall settings card in the
 * settings plugin section (a sibling of the built-in Shell / Agent loop /
 * Web search cards). There is no ball to render in the web UI: the desktop
 * app owns the visuals and consumes the host's `GET /api/moodball/status`.
 * @module @linxin666/dsh-moodball-status/client
 */
import type { ClientContext } from '@deepseek-ai/dsh-client-runtime/client';
/** Required services. */
export declare const inject: string[];
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
        'settings.plugin.item': {
            kind: 'list';
            scope: 'root';
            owner: SettingsPluginItemOwnerProps;
        };
    }
}
/** Owner share of a plugin card (the settings section supplies nothing). */
export interface SettingsPluginItemOwnerProps {
    /** Marker field: card owner props are intentionally empty. */
    children?: never;
}
/**
 * Client plugin body: register dictionaries and seat the settings card in the
 * settings plugin section.
 * @param ctx - client root context.
 */
export declare function apply(ctx: ClientContext): void;
