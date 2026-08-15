import Foundation
import SwiftUI
import Combine

// MARK: - 接口响应（与 dsh-waterball 插件一致）

struct WaterballStatus: Decodable {
    let ok: Bool
    let mood: String
    let enabled: Bool?
    let size: Int?
    let right: Int?
    let bottom: Int?
}

// MARK: - 连接状态（区分两种「灰」）

enum ConnectionState {
    case connected              // 正常拿到 mood
    case pluginDisabled         // 接口 404：插件 enabled=false（网页球 hidden 不影响桌面球）
    case unreachable            // 连接失败/非 200：DSH 未运行等
}

// MARK: - mood 说明（颜色由 SettingsStore 提供，可在设置面板自定义）

enum MoodColorMap {
    static func label(for mood: String) -> String {
        switch mood {
        case "idle":     return "空闲"
        case "waiting":  return "思考中"
        case "jumping":  return "工具调用"
        case "authorizing": return "授权等待"
        case "done":     return "完成"
        case "failed":   return "出错"
        case "stopped":  return "已停止"
        default:         return "未知"
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

// MARK: - 全局状态：按设置轮询 /api/waterball/status

@MainActor
final class WaterballModel: ObservableObject {
    static let shared = WaterballModel()

    @Published private(set) var connected = false
    @Published private(set) var mood = "idle"
    @Published private(set) var ballSize: CGFloat = 120
    @Published private(set) var color: Color = Color(hex: 0x9ca3af)
    @Published private(set) var moodLabel = "未连接"
    @Published private(set) var breathingPeriod: Double = 2.0
    @Published private(set) var connectionState: ConnectionState = .unreachable

    /// 菜单栏/状态文案
    var statusText: String {
        switch connectionState {
        case .connected: return "已连接 · \(moodLabel)"
        case .pluginDisabled: return "插件已关闭（灰球）"
        case .unreachable: return "DSH 未运行（灰球）"
        }
    }

    /// 状态气泡文字：空闲/断连/禁用时不显示；其余状态显示中文状态名（思考中/工具调用…）。
    /// 由 WaterballView 渲染在球脑门上方，AppDelegate 监听 mood 变化同步面板高度。
    var bubbleText: String? {
        switch mood {
        case "idle", "unreachable", "disabled":
            return nil
        default:
            return moodLabel
        }
    }

    /// 悬浮球显隐（菜单栏「显示/隐藏」切换）
    @Published var isBallVisible = true

    private var timer: Timer?
    private var settingsCancellable: AnyCancellable?

    /// 当前要轮询的完整 URL（跟随设置里的 apiBase）
    private var statusURL: URL? {
        let base = SettingsStore.shared.apiBase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard !base.isEmpty, let url = URL(string: base + "/api/waterball/status") else { return nil }
        return url
    }

    func start() {
        guard timer == nil else { return }
        poll() // 立即先拉一次
        scheduleTimer()

        // apiBase / 轮询间隔变化时，动态重建 Timer 并立即刷新
        let changes: [AnyPublisher<Void, Never>] = [
            SettingsStore.shared.$apiBase.map { _ in () as Void }.eraseToAnyPublisher(),
            SettingsStore.shared.$pollInterval.map { _ in () as Void }.eraseToAnyPublisher(),
        ]
        settingsCancellable = Publishers.MergeMany(changes)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleTimer()
                self?.poll()
            }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        settingsCancellable?.cancel()
        settingsCancellable = nil
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = SettingsStore.shared.pollInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    private func poll() {
        guard let url = statusURL else {
            applyUnreachable()
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: SettingsStore.shared.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if http.statusCode == 404 {
                    // 插件被禁用（enabled=false）：路由被移除 → 灰球「插件已关闭」
                    applyPluginDisabled()
                    return
                }
                guard http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let status = try JSONDecoder().decode(WaterballStatus.self, from: data)
                apply(status)
            } catch {
                applyUnreachable()
            }
        }
    }

    private func apply(_ status: WaterballStatus) {
        guard status.ok else {
            applyUnreachable()
            return
        }
        // 大小：本地设置优先（球已独立，不再跟随网页）
        ballSize = SettingsStore.shared.ballSize
        if status.enabled == false {
            applyPluginDisabled()
            return
        }
        connected = true
        connectionState = .connected
        mood = status.mood
        moodLabel = MoodColorMap.label(for: status.mood)
        color = SettingsStore.shared.moodColors[status.mood] ?? Color(hex: 0x9ca3af)
        breathingPeriod = SettingsStore.shared.breathingSpeed // 全局统一呼吸速度
    }

    private func applyPluginDisabled() {
        connected = false
        connectionState = .pluginDisabled
        mood = "disabled"
        color = SettingsStore.shared.disconnectedColor
        moodLabel = "插件已关闭"
        breathingPeriod = SettingsStore.shared.breathingSpeed
    }

    private func applyUnreachable() {
        connected = false
        connectionState = .unreachable
        mood = "unreachable"
        color = SettingsStore.shared.disconnectedColor
        moodLabel = "DSH 未运行"
        breathingPeriod = SettingsStore.shared.breathingSpeed
    }
}
