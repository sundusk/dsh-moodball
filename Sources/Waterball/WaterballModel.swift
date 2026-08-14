import Foundation
import SwiftUI

// MARK: - 接口响应（与 dsh-waterball 插件一致）

struct WaterballStatus: Decodable {
    let ok: Bool
    let mood: String
    let enabled: Bool?
    let size: Int?
    let right: Int?
    let bottom: Int?
}

// MARK: - mood → 颜色映射（README 中唯一要遵守的契约）

struct MoodEntry {
    let label: String      // 中文说明（菜单栏展示用）
    let color: Color       // 球体颜色
    let period: Double     // 呼吸周期（秒），忙碌态快、空闲慢
}

enum MoodColorMap {
    static let disconnected = MoodEntry(label: "未连接", color: Color(hex: 0x9ca3af), period: 3.0)
    static let disabled = MoodEntry(label: "已禁用", color: Color(hex: 0x9ca3af), period: 3.0)
    static let unknown = MoodEntry(label: "未知", color: Color(hex: 0x9ca3af), period: 3.0)

    static func entry(for mood: String) -> MoodEntry {
        switch mood {
        case "idle":     return MoodEntry(label: "空闲",   color: Color(hex: 0x60a5fa), period: 2.8) // 蓝
        case "waiting":  return MoodEntry(label: "思考中", color: Color(hex: 0x34d399), period: 1.0) // 绿
        case "jumping":  return MoodEntry(label: "工具调用", color: Color(hex: 0xa855f7), period: 0.8) // 紫
        case "done":     return MoodEntry(label: "完成",   color: Color(hex: 0x22d3ee), period: 1.6) // 青
        case "failed":   return MoodEntry(label: "出错",   color: Color(hex: 0xf87171), period: 1.2) // 红
        case "stopped":  return MoodEntry(label: "已停止", color: Color(hex: 0x000000), period: 3.0) // 黑
        case "waving":   return MoodEntry(label: "挥手",   color: Color(hex: 0xfb923c), period: 1.4) // 橙
        default:         return unknown
        }
    }
}

extension Color {
    /// 0xRRGGBB → Color
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - 全局状态：700ms 轮询 /api/waterball/status

@MainActor
final class WaterballModel: ObservableObject {
    static let shared = WaterballModel()

    /// 轮询间隔，与网页插件一致：700ms
    static let pollInterval: TimeInterval = 0.7
    static let statusURL = URL(string: "http://127.0.0.1:3080/api/waterball/status")!
    /// 请求超时：DSH 关闭时快速判为「未连接」
    static let requestTimeout: TimeInterval = 2.0

    @Published private(set) var connected = false
    @Published private(set) var mood = "idle"
    @Published private(set) var ballSize: CGFloat = 120
    @Published private(set) var color: Color = MoodColorMap.disconnected.color
    @Published private(set) var moodLabel = MoodColorMap.disconnected.label
    @Published private(set) var breathingPeriod: Double = MoodColorMap.disconnected.period

    /// 悬浮球显隐（菜单栏「显示/隐藏」切换）
    @Published var isBallVisible = true

    var statusText: String {
        connected ? "已连接 · \(moodLabel)" : "\(moodLabel)（DSH 未运行）"
    }

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        poll() // 立即先拉一次
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        var request = URLRequest(url: Self.statusURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let status = try JSONDecoder().decode(WaterballStatus.self, from: data)
                apply(status)
            } catch {
                applyDisconnected()
            }
        }
    }

    private func apply(_ status: WaterballStatus) {
        guard status.ok else {
            applyDisconnected()
            return
        }
        if let size = status.size, size > 0 {
            ballSize = CGFloat(size)
        }
        if status.enabled == false {
            // 插件主开关关闭 → 灰球
            connected = false
            mood = "disabled"
            color = MoodColorMap.disabled.color
            moodLabel = MoodColorMap.disabled.label
            breathingPeriod = MoodColorMap.disabled.period
            return
        }
        connected = true
        mood = status.mood
        let entry = MoodColorMap.entry(for: status.mood)
        color = entry.color
        moodLabel = entry.label
        breathingPeriod = entry.period
    }

    private func applyDisconnected() {
        connected = false
        mood = "disconnected"
        color = MoodColorMap.disconnected.color
        moodLabel = MoodColorMap.disconnected.label
        breathingPeriod = MoodColorMap.disconnected.period
    }
}
