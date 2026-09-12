import Foundation
import SwiftUI

// MARK: - 状态颜色契约

struct MoodColorConfig {
    let mood: String
    let label: String
    let defaultHex: UInt32
}

let moodColorConfigs: [MoodColorConfig] = [
    MoodColorConfig(mood: "idle", label: "空闲", defaultHex: 0x60a5fa),
    MoodColorConfig(mood: "waiting", label: "正在思考中", defaultHex: 0x34d399),
    MoodColorConfig(mood: "jumping", label: "工具调用", defaultHex: 0xa855f7),
    MoodColorConfig(mood: "authorizing", label: "等待你的授权", defaultHex: 0xfacc15),
    MoodColorConfig(mood: "questioning", label: "做出你的抉择", defaultHex: 0xec4899),
    MoodColorConfig(mood: "done", label: "搞定啦", defaultHex: 0x22d3ee),
    MoodColorConfig(mood: "failed", label: "出错了", defaultHex: 0xf87171),
    MoodColorConfig(mood: "stopped", label: "已停止", defaultHex: 0x000000),
]

let disconnectedHex: UInt32 = 0x9ca3af

// MARK: - 桌宠类型与通用设置

enum FloatingPetSkin: String, CaseIterable, Identifiable {
    case moodBall
    case xiaoyu

    var id: String { rawValue }

    var label: String {
        switch self {
        case .moodBall: return "心情球"
        case .xiaoyu: return "小雨"
        }
    }
}

enum ClickThroughMode: String, CaseIterable, Identifiable {
    case hover
    case always
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hover: return "悬停时恢复响应"
        case .always: return "永远点击穿透"
        case .never: return "永不穿透"
        }
    }
}

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

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

/// Shared pet settings. New values live under `moodball.*`; old `settings.*`
/// values are read as a compatibility fallback.
@MainActor
final class PetSettings: ObservableObject {
    static let shared = PetSettings()

    private let defaults: UserDefaults

    private enum Key {
        static let skin = "moodball.skin"
        static let ballSize = "moodball.ballSize"
        static let breathingSpeed = "moodball.breathingSpeed"
        static let apiBase = "moodball.apiBase"
        static let pollInterval = "moodball.pollInterval"
        static let requestTimeout = "moodball.requestTimeout"
        static let clickThrough = "moodball.clickThrough"
        static let rememberPosition = "moodball.rememberPosition"
        static let showEyes = "moodball.showEyes"
        static let eyeColor = "moodball.eyeColor"
        static let showStatusBubble = "moodball.showStatusBubble"
        static let glowEnabled = "moodball.glowEnabled"
        static let lockPosition = "moodball.lockPosition"
        static let isBallVisible = "moodball.isBallVisible"
        static let positionX = "moodball.ballPositionX"
        static let positionY = "moodball.ballPositionY"
        static let moodColorPrefix = "moodball.moodColor."
    }

    private enum LegacyKey {
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
        static let glowEnabled = "settings.glowEnabled"
        static let lockPosition = "settings.lockPosition"
        static let positionX = "ballPositionX"
        static let positionY = "ballPositionY"
        static let moodColorPrefix = "settings.moodColor."
    }

    @Published var skin: FloatingPetSkin {
        didSet { defaults.set(skin.rawValue, forKey: Key.skin) }
    }

    @Published var ballSize: CGFloat {
        didSet { defaults.set(Double(ballSize), forKey: Key.ballSize) }
    }

    @Published var breathingSpeed: Double {
        didSet { defaults.set(breathingSpeed, forKey: Key.breathingSpeed) }
    }

    @Published var showStatusBubble: Bool {
        didSet { defaults.set(showStatusBubble, forKey: Key.showStatusBubble) }
    }

    @Published var glowEnabled: Bool {
        didSet { defaults.set(glowEnabled, forKey: Key.glowEnabled) }
    }

    @Published var isBallVisible: Bool {
        didSet { defaults.set(isBallVisible, forKey: Key.isBallVisible) }
    }

    @Published var lockPosition: Bool {
        didSet { defaults.set(lockPosition, forKey: Key.lockPosition) }
    }

    @Published var showEyes: Bool {
        didSet { defaults.set(showEyes, forKey: Key.showEyes) }
    }

    @Published var eyeColor: EyeColor {
        didSet { defaults.set(eyeColor.rawValue, forKey: Key.eyeColor) }
    }

    @Published var apiBase: String {
        didSet { defaults.set(apiBase, forKey: Key.apiBase) }
    }

    @Published var pollInterval: Double {
        didSet { defaults.set(pollInterval, forKey: Key.pollInterval) }
    }

    @Published var requestTimeout: Double {
        didSet { defaults.set(requestTimeout, forKey: Key.requestTimeout) }
    }

    @Published var clickThroughMode: ClickThroughMode {
        didSet { defaults.set(clickThroughMode.rawValue, forKey: Key.clickThrough) }
    }

    @Published var rememberPosition: Bool {
        didSet { defaults.set(rememberPosition, forKey: Key.rememberPosition) }
    }

    @Published private(set) var moodColors: [String: Color] = [:]

    @Published var disconnectedColor: Color {
        didSet { writeColor(disconnectedColor, key: Key.moodColorPrefix + "disconnected") }
    }

    var savedBallPosition: CGPoint? {
        get {
            guard let x = Self.number(defaults, for: Key.positionX, legacy: LegacyKey.positionX),
                  let y = Self.number(defaults, for: Key.positionY, legacy: LegacyKey.positionY) else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            if let newValue {
                defaults.set(Double(newValue.x), forKey: Key.positionX)
                defaults.set(Double(newValue.y), forKey: Key.positionY)
            } else {
                defaults.removeObject(forKey: Key.positionX)
                defaults.removeObject(forKey: Key.positionY)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let clamp = { (value: Double, lower: Double, upper: Double) in min(max(value, lower), upper) }

        skin = FloatingPetSkin(rawValue: defaults.string(forKey: Key.skin) ?? "") ?? .xiaoyu
        ballSize = CGFloat(clamp(Self.number(defaults, for: Key.ballSize, legacy: LegacyKey.ballSize) ?? 120, 60, 200))
        breathingSpeed = clamp(Self.number(defaults, for: Key.breathingSpeed, legacy: LegacyKey.breathingSpeed) ?? 2, 0.5, 5)
        apiBase = Self.string(defaults, for: Key.apiBase, legacy: LegacyKey.apiBase) ?? "http://127.0.0.1:3080"
        pollInterval = clamp(Self.number(defaults, for: Key.pollInterval, legacy: LegacyKey.pollInterval) ?? 0.7, 0.3, 5)
        requestTimeout = clamp(Self.number(defaults, for: Key.requestTimeout, legacy: LegacyKey.requestTimeout) ?? 2, 0.5, 5)
        clickThroughMode = ClickThroughMode(rawValue: Self.string(defaults, for: Key.clickThrough, legacy: LegacyKey.clickThrough) ?? "") ?? .hover
        rememberPosition = Self.bool(defaults, for: Key.rememberPosition, legacy: LegacyKey.rememberPosition) ?? true
        showEyes = Self.bool(defaults, for: Key.showEyes, legacy: LegacyKey.showEyes) ?? true
        eyeColor = EyeColor(rawValue: Self.string(defaults, for: Key.eyeColor, legacy: LegacyKey.eyeColor) ?? "") ?? .black
        showStatusBubble = Self.bool(defaults, for: Key.showStatusBubble, legacy: LegacyKey.showStatusBubble) ?? true
        glowEnabled = Self.bool(defaults, for: Key.glowEnabled, legacy: LegacyKey.glowEnabled) ?? true
        lockPosition = Self.bool(defaults, for: Key.lockPosition, legacy: LegacyKey.lockPosition) ?? false
        isBallVisible = defaults.object(forKey: Key.isBallVisible) == nil ? true : defaults.bool(forKey: Key.isBallVisible)
        disconnectedColor = Color(hex: Self.hex(defaults, for: Key.moodColorPrefix + "disconnected", legacy: LegacyKey.moodColorPrefix + "disconnected") ?? disconnectedHex)

        var colors: [String: Color] = [:]
        for config in moodColorConfigs {
            let key = Key.moodColorPrefix + config.mood
            let legacy = LegacyKey.moodColorPrefix + config.mood
            colors[config.mood] = Color(hex: Self.hex(defaults, for: key, legacy: legacy) ?? config.defaultHex)
        }
        moodColors = colors
    }

    func setMoodColor(_ mood: String, _ color: Color) {
        moodColors[mood] = color
        writeColor(color, key: Key.moodColorPrefix + mood)
    }

    func resetMoodColors() {
        var colors: [String: Color] = [:]
        for config in moodColorConfigs {
            colors[config.mood] = Color(hex: config.defaultHex)
            defaults.removeObject(forKey: Key.moodColorPrefix + config.mood)
        }
        moodColors = colors
        disconnectedColor = Color(hex: disconnectedHex)
        defaults.removeObject(forKey: Key.moodColorPrefix + "disconnected")
    }

    func resetPositionRequested() {
        NotificationCenter.default.post(name: .waterballResetPosition, object: nil)
    }

    private static func storedValue(_ defaults: UserDefaults, for key: String, legacy: String) -> Any? {
        defaults.object(forKey: key) ?? defaults.object(forKey: legacy)
    }

    private static func number(_ defaults: UserDefaults, for key: String, legacy: String) -> Double? {
        if let number = storedValue(defaults, for: key, legacy: legacy) as? NSNumber { return number.doubleValue }
        if let string = storedValue(defaults, for: key, legacy: legacy) as? String { return Double(string) }
        return nil
    }

    private static func string(_ defaults: UserDefaults, for key: String, legacy: String) -> String? {
        if let string = storedValue(defaults, for: key, legacy: legacy) as? String { return string }
        if let number = storedValue(defaults, for: key, legacy: legacy) as? NSNumber { return number.stringValue }
        return nil
    }

    private static func bool(_ defaults: UserDefaults, for key: String, legacy: String) -> Bool? {
        guard storedValue(defaults, for: key, legacy: legacy) != nil else { return nil }
        return defaults.bool(forKey: defaults.object(forKey: key) != nil ? key : legacy)
    }

    private static func hex(_ defaults: UserDefaults, for key: String, legacy: String) -> UInt32? {
        if let string = defaults.object(forKey: key) as? String ?? defaults.object(forKey: legacy) as? String {
            return UInt32(string, radix: 16)
        }
        if let number = defaults.object(forKey: key) as? NSNumber ?? defaults.object(forKey: legacy) as? NSNumber {
            return number.uint32Value
        }
        return nil
    }

    private func writeColor(_ color: Color, key: String) {
        defaults.set(String(format: "%06X", colorToHex(color)), forKey: key)
    }
}

/// Compatibility name retained while downstream source adopts `PetSettings`.
typealias SettingsStore = PetSettings

extension Notification.Name {
    static let waterballResetPosition = Notification.Name("waterballResetPosition")
    static let waterballToggleSettings = Notification.Name("waterballToggleSettings")
}

func colorToHex(_ color: Color) -> UInt32 {
    let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    let r = Int((resolved.redComponent * 255).rounded())
    let g = Int((resolved.greenComponent * 255).rounded())
    let b = Int((resolved.blueComponent * 255).rounded())
    return UInt32(r << 16 | g << 8 | b)
}
