import Foundation
import SwiftUI

// MARK: - 可配置的 7 色映射（与 README 契约一致，可被设置面板覆盖）

struct MoodColorConfig {
    let mood: String
    let label: String
    let defaultHex: UInt32
}

/// 7 个 mood 的颜色配置（顺序固定；waving 是网页端交互态，桌面球用不到故不含）
let moodColorConfigs: [MoodColorConfig] = [
    MoodColorConfig(mood: "idle",         label: "空闲",   defaultHex: 0x60a5fa), // 蓝
    MoodColorConfig(mood: "waiting",      label: "正在思考中", defaultHex: 0x34d399), // 绿
    MoodColorConfig(mood: "jumping",      label: "工具调用", defaultHex: 0xa855f7), // 紫
    MoodColorConfig(mood: "authorizing",  label: "等待你的授权", defaultHex: 0xfacc15), // 黄
    MoodColorConfig(mood: "done",         label: "搞定啦",   defaultHex: 0x22d3ee), // 青
    MoodColorConfig(mood: "failed",       label: "出错",   defaultHex: 0xf87171), // 红
    MoodColorConfig(mood: "stopped",      label: "已停止", defaultHex: 0x000000), // 黑
]

/// 断连/禁用时的灰色
let disconnectedHex: UInt32 = 0x9ca3af

// MARK: - 穿透模式

enum ClickThroughMode: String, CaseIterable, Identifiable {
    case hover     // 悬停时恢复响应（默认）
    case always    // 永远穿透（不可拖拽）
    case never     // 永不穿透（常驻响应）

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hover: return "悬停时恢复响应"
        case .always: return "永远点击穿透"
        case .never: return "永不穿透"
        }
    }
}

// MARK: - 眼睛颜色（仅黑白两色）

enum EyeColor: String, CaseIterable, Identifiable {
    case white
    case black

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: return "白色"
        case .black: return "黑色"
        }
    }

    var color: Color {
        switch self {
        case .white: return .white
        case .black: return .black
        }
    }
}

// MARK: - 全局设置（UserDefaults 持久化）

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    // 键名
    private enum Key {
        static let ballSize = "settings.ballSize"
        static let breathingSpeed = "settings.breathingSpeed"
        static let apiBase = "settings.apiBase"
        static let pollInterval = "settings.pollInterval"
        static let requestTimeout = "settings.requestTimeout"
        static let clickThrough = "settings.clickThrough"
        static let rememberPosition = "settings.rememberPosition"
        static let showEyes = "settings.showEyes"
        static let eyeColor = "settings.eyeColor"
        static let showStatusBubble = "settings.showStatusBubble"
        static let moodColorPrefix = "settings.moodColor."
    }

    // MARK: 外观

    /// 球体直径 60–200，默认 120
    @Published var ballSize: CGFloat {
        didSet { defaults.set(Double(ballSize), forKey: Key.ballSize) }
    }

    /// 呼吸周期（秒）0.5–5，默认 2.0（全局统一，简单优先）
    @Published var breathingSpeed: Double {
        didSet { defaults.set(breathingSpeed, forKey: Key.breathingSpeed) }
    }

    /// 是否显示水球眼睛（白色竖椭圆），默认开
    @Published var showEyes: Bool {
        didSet { defaults.set(showEyes, forKey: Key.showEyes) }
    }

    /// 眼睛颜色（仅黑白两色），默认白
    @Published var eyeColor: EyeColor {
        didSet { defaults.set(eyeColor.rawValue, forKey: Key.eyeColor) }
    }

    /// 状态气泡：非空闲时在球脑门上方显示中文状态提醒，默认开
    @Published var showStatusBubble: Bool {
        didSet { defaults.set(showStatusBubble, forKey: Key.showStatusBubble) }
    }

    // MARK: 行为

    /// API 基地址，默认 http://127.0.0.1:3080
    @Published var apiBase: String {
        didSet { defaults.set(apiBase, forKey: Key.apiBase) }
    }

    /// 轮询间隔（秒）0.3–5，默认 0.7
    @Published var pollInterval: Double {
        didSet { defaults.set(pollInterval, forKey: Key.pollInterval) }
    }

    /// 请求超时（秒）0.5–5，默认 2
    @Published var requestTimeout: Double {
        didSet { defaults.set(requestTimeout, forKey: Key.requestTimeout) }
    }

    /// 点击穿透模式
    @Published var clickThroughMode: ClickThroughMode {
        didSet { defaults.set(clickThroughMode.rawValue, forKey: Key.clickThrough) }
    }

    /// 记住拖拽位置（重启恢复）
    @Published var rememberPosition: Bool {
        didSet { defaults.set(rememberPosition, forKey: Key.rememberPosition) }
    }

    // MARK: 颜色

    /// 当前 mood → 颜色（跟随 mood 永远生效；颜色可自定义）
    @Published private(set) var moodColors: [String: Color] = [:]

    /// 断连/禁用灰
    @Published var disconnectedColor: Color {
        didSet {
            // 存 hex
            defaults.set(colorToHex(disconnectedColor), forKey: Key.moodColorPrefix + "disconnected")
        }
    }

    init() {
        let d = UserDefaults.standard
        let clamp = { (v: Double, lo: Double, hi: Double) in min(max(v, lo), hi) }

        ballSize = CGFloat(clamp(d.double(forKey: Key.ballSize) == 0 ? 120 : d.double(forKey: Key.ballSize), 60, 200))
        breathingSpeed = clamp(d.double(forKey: Key.breathingSpeed) == 0 ? 2.0 : d.double(forKey: Key.breathingSpeed), 0.5, 5)
        apiBase = d.string(forKey: Key.apiBase) ?? "http://127.0.0.1:3080"
        pollInterval = clamp(d.double(forKey: Key.pollInterval) == 0 ? 0.7 : d.double(forKey: Key.pollInterval), 0.3, 5)
        requestTimeout = clamp(d.double(forKey: Key.requestTimeout) == 0 ? 2.0 : d.double(forKey: Key.requestTimeout), 0.5, 5)
        clickThroughMode = ClickThroughMode(rawValue: d.string(forKey: Key.clickThrough) ?? "") ?? .hover
        rememberPosition = d.object(forKey: Key.rememberPosition) == nil ? true : d.bool(forKey: Key.rememberPosition)
        showEyes = d.object(forKey: Key.showEyes) == nil ? true : d.bool(forKey: Key.showEyes)
        eyeColor = EyeColor(rawValue: d.string(forKey: Key.eyeColor) ?? "") ?? .white
        showStatusBubble = d.object(forKey: Key.showStatusBubble) == nil ? true : d.bool(forKey: Key.showStatusBubble)
        disconnectedColor = Color(hex: hexFromDefaults(d, key: Key.moodColorPrefix + "disconnected") ?? disconnectedHex)

        // 读 7 色（没存过就用契约默认值）
        var colors: [String: Color] = [:]
        for cfg in moodColorConfigs {
            let hex = hexFromDefaults(d, key: Key.moodColorPrefix + cfg.mood) ?? cfg.defaultHex
            colors[cfg.mood] = Color(hex: hex)
        }
        moodColors = colors
    }

    /// 设置某个 mood 的颜色
    func setMoodColor(_ mood: String, _ color: Color) {
        moodColors[mood] = color
        defaults.set(colorToHex(color), forKey: Key.moodColorPrefix + mood)
    }

    /// 全部恢复契约默认色
    func resetMoodColors() {
        var colors: [String: Color] = [:]
        for cfg in moodColorConfigs {
            colors[cfg.mood] = Color(hex: cfg.defaultHex)
            defaults.removeObject(forKey: Key.moodColorPrefix + cfg.mood)
        }
        moodColors = colors
        disconnectedColor = Color(hex: disconnectedHex)
        defaults.removeObject(forKey: Key.moodColorPrefix + "disconnected")
    }

    /// 位置重置（交给 AppDelegate 执行实际定位）
    func resetPositionRequested() {
        NotificationCenter.default.post(name: .waterballResetPosition, object: nil)
    }
}

extension Notification.Name {
    /// 设置面板「位置重置」请求
    static let waterballResetPosition = Notification.Name("waterballResetPosition")
    /// 菜单栏「设置…」请求（AppDelegate 监听后打开/关闭设置面板）
    static let waterballToggleSettings = Notification.Name("waterballToggleSettings")
}

// MARK: - hex 工具

func colorToHex(_ color: Color) -> UInt32 {
    let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    let r = Int((resolved.redComponent * 255).rounded())
    let g = Int((resolved.greenComponent * 255).rounded())
    let b = Int((resolved.blueComponent * 255).rounded())
    return UInt32(r << 16 | g << 8 | b)
}

func hexFromDefaults(_ d: UserDefaults, key: String) -> UInt32? {
    let raw = d.string(forKey: key)
    guard let raw, let value = UInt32(raw, radix: 16) else { return nil }
    return value
}
