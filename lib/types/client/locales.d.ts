/**
 * dsh-moodball-status locale dictionaries (zh/en).
 * @module @linxin666/dsh-moodball-status/client/locales
 */
/** Dictionary namespace this package registers. */
export declare const NS = "moodball";
/** Chinese copy. */
export declare const zh: {
    readonly 'settings.title': "心情球";
    readonly 'settings.description': "为 MoodBall 桌面 app 提供 agent 状态接口（/api/moodball/status）。桌面右下角的发光呼吸球随 Agent 状态变色。";
    readonly 'settings.enabled': "启用心情球";
    readonly 'settings.enabledHint': "关闭后移除状态接口，桌面球变为灰色「插件已关闭」；可在此重新启用。";
    readonly 'settings.inherit': "继承";
    readonly 'settings.on': "开";
    readonly 'settings.off': "关";
    readonly 'settings.overridden': "已覆盖";
    readonly 'settings.reset': "恢复默认";
    readonly 'settings.readOnly': "当前部署的设置只读。";
    readonly 'settings.expand': "展开设置";
    readonly 'settings.collapse': "收起设置";
    readonly 'settings.save': "保存";
    readonly 'settings.saving': "保存中…";
    readonly 'settings.discard': "放弃";
    readonly 'settings.unsaved': "未保存";
    readonly 'settings.saveFailed': "部署未接受这些值，已保留供你修改。";
    readonly 'settings.invalidNumber': "请输入数字，留空则使用默认值。";
};
/** English copy. */
export declare const en: {
    readonly 'settings.title': "MoodBall";
    readonly 'settings.description': "Serves the agent status API (/api/moodball/status) for the MoodBall desktop app — a glowing breathing ball that changes color with agent activity.";
    readonly 'settings.enabled': "Enable MoodBall";
    readonly 'settings.enabledHint': "When off, the status API is removed and the desktop ball turns gray (plugin off); re-enable it here.";
    readonly 'settings.inherit': "Inherit";
    readonly 'settings.on': "On";
    readonly 'settings.off': "Off";
    readonly 'settings.overridden': "Overridden";
    readonly 'settings.reset': "Reset to default";
    readonly 'settings.readOnly': "This deployment stores settings read-only.";
    readonly 'settings.expand': "Show settings";
    readonly 'settings.collapse': "Hide settings";
    readonly 'settings.save': "Save";
    readonly 'settings.saving': "Saving…";
    readonly 'settings.discard': "Discard";
    readonly 'settings.unsaved': "Unsaved";
    readonly 'settings.saveFailed': "The deployment did not accept these values; they were left for you to correct.";
    readonly 'settings.invalidNumber': "Enter a number, or leave blank to use the default.";
};
/** Key union for this namespace. */
export type MoodballKey = keyof typeof zh;
/** The settings-card slice of the moodball dictionary. */
export type SettingsCardKey = MoodballKey;
declare module '@deepseek-ai/dsh-client-ui-slots' {
    interface LocaleNamespaceMap {
        /** dsh-moodball-status UI copy. */
        moodball: MoodballKey;
    }
}
