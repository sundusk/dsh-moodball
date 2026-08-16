/**
 * dsh-moodball-status locale dictionaries (zh/en).
 * @module @linxin666/dsh-moodball-status/client/locales
 */

/** Dictionary namespace this package registers. */
export const NS = 'moodball'

/** Chinese copy. */
export const zh = {
  'settings.title': '心情球',
  'settings.description': '为 MoodBall 桌面 app 提供 agent 状态接口（/api/moodball/status）。桌面右下角的发光呼吸球随 Agent 状态变色。',
  'settings.enabled': '启用心情球',
  'settings.enabledHint': '关闭后移除状态接口，桌面球变为灰色「插件已关闭」；可在此重新启用。',
  'settings.inherit': '继承',
  'settings.on': '开',
  'settings.off': '关',
  'settings.overridden': '已覆盖',
  'settings.reset': '恢复默认',
  'settings.readOnly': '当前部署的设置只读。',
  'settings.expand': '展开设置',
  'settings.collapse': '收起设置',
  'settings.save': '保存',
  'settings.saving': '保存中…',
  'settings.discard': '放弃',
  'settings.unsaved': '未保存',
  'settings.saveFailed': '部署未接受这些值，已保留供你修改。',
  'settings.invalidNumber': '请输入数字，留空则使用默认值。',
} as const

/** English copy. */
export const en = {
  'settings.title': 'MoodBall',
  'settings.description': 'Serves the agent status API (/api/moodball/status) for the MoodBall desktop app — a glowing breathing ball that changes color with agent activity.',
  'settings.enabled': 'Enable MoodBall',
  'settings.enabledHint': 'When off, the status API is removed and the desktop ball turns gray (plugin off); re-enable it here.',
  'settings.inherit': 'Inherit',
  'settings.on': 'On',
  'settings.off': 'Off',
  'settings.overridden': 'Overridden',
  'settings.reset': 'Reset to default',
  'settings.readOnly': 'This deployment stores settings read-only.',
  'settings.expand': 'Show settings',
  'settings.collapse': 'Hide settings',
  'settings.save': 'Save',
  'settings.saving': 'Saving\u2026',
  'settings.discard': 'Discard',
  'settings.unsaved': 'Unsaved',
  'settings.saveFailed': 'The deployment did not accept these values; they were left for you to correct.',
  'settings.invalidNumber': 'Enter a number, or leave blank to use the default.',
} as const

/** Key union for this namespace. */
export type MoodballKey = keyof typeof zh

/** The settings-card slice of the moodball dictionary. */
export type SettingsCardKey = MoodballKey

declare module '@deepseek-ai/dsh-client-ui-slots' {
  interface LocaleNamespaceMap {
    /** dsh-moodball-status UI copy. */
    moodball: MoodballKey
  }
}
