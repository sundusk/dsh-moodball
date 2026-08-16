import SwiftUI
import AppKit

/// 状态展示面板：选择一个状态，实时展示对应颜色的小球（真实渲染、静态满状态），
/// 可切换显示/隐藏气泡文字，方便逐个状态截图用于 README 等文档。
struct StatePreviewPanelView: View {
    @ObservedObject private var settings = SettingsStore.shared

    /// 展示用状态列表（与 README 颜色含义一致；waving 是网页交互态，桌面球不含）
    private static let states: [(mood: String, label: String)] = [
        ("idle", "空闲"),
        ("waiting", "正在思考中"),
        ("jumping", "工具调用"),
        ("authorizing", "等待你的授权"),
        ("questioning", "做出你的抉择"),
        ("done", "搞定啦"),
        ("failed", "出错了"),
        ("stopped", "已停止"),
        ("disconnected", "未连接"),
    ]

    @State private var selectedMood = "idle"
    /// 是否在球上方显示气泡文字（默认关，便于截图纯球）
    @State private var showText = false
    /// 导出 PNG 的反馈信息
    @State private var exportMessage: String?

    private var selectedColor: Color {
        if selectedMood == "disconnected" {
            return settings.disconnectedColor
        }
        return settings.moodColors[selectedMood] ?? Color(hex: 0x60a5fa)
    }

    private var selectedLabel: String {
        Self.states.first { $0.mood == selectedMood }?.label ?? "空闲"
    }

    /// 气泡文字：与真实 app 一致——空闲/未连接不显示气泡，其余状态显示状态名
    private var previewBubbleText: String? {
        guard showText else { return nil }
        switch selectedMood {
        case "idle", "disconnected":
            return nil
        default:
            return selectedLabel
        }
    }

    private func dotColor(_ mood: String) -> Color {
        if mood == "disconnected" {
            return settings.disconnectedColor
        }
        return settings.moodColors[mood] ?? Color(hex: 0x60a5fa)
    }

    /// 导出当前状态的小球为固定 512×512 透明背景 PNG（真实渲染，尺寸一致，免截图裁剪）。
    /// 「显示文字」打开时，气泡会一并导出。
    private func exportPNG() {
        let mood = selectedMood
        let color = selectedColor
        let text = previewBubbleText
        // 固定画布：球 280px，光晕 1.7×280=476px 完整落在 512 画布内；气泡随组合渲染
        let canvas = BallWithBubble(mood: mood, color: color, size: 280, text: text)
            .frame(width: 512, height: 512)
            .clipped()

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            exportMessage = "导出失败"
            return
        }
        let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("moodball-\(mood).png")
        do {
            try png.write(to: url)
            exportMessage = "已保存：桌面/moodball-\(mood).png"
        } catch {
            exportMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // 小球展示区：浅色底便于截图，球与真实渲染一致；可选气泡文字
            ZStack {
                Color.black.opacity(0.05)
                BallWithBubble(mood: selectedMood, color: selectedColor, size: 130, text: previewBubbleText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Text("展示：\(selectedLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("保存 PNG") { exportPNG() }
                    .controlSize(.small)
                Toggle(showText ? "隐藏文字" : "显示文字", isOn: $showText)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if let message = exportMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 状态选择网格（3 列）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Self.states, id: \.mood) { state in
                    Button {
                        selectedMood = state.mood
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(dotColor(state.mood))
                                .frame(width: 10, height: 10)
                            Text(state.label)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedMood == state.mood ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selectedMood == state.mood ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

/// 球 + 可选气泡的组合（与真实 app 布局一致：气泡尾巴尖端贴球顶，间距 = tailGap）。
/// 预览（130px）与导出 PNG（280px）共用，保证所见即所存。
private struct BallWithBubble: View {
    let mood: String
    let color: Color
    let size: CGFloat
    let text: String?

    var body: some View {
        ZStack(alignment: .top) {
            StateBallPreview(mood: mood, color: color, size: size)
            if let text {
                SpeechBubble(text: text, color: color)
                    .offset(y: size / 2 - MoodBallView.bubbleHeight - MoodBallView.tailGap)
            }
        }
    }
}

/// 状态展示用的小球：与真实桌面球一致的渲染
/// （外发光 + 渐变球体 + 高光 + 眼睛 + stopped 白环），静态满状态、无气泡文字。
struct StateBallPreview: View {
    @ObservedObject private var settings = SettingsStore.shared
    let mood: String
    let color: Color
    let size: CGFloat

    var body: some View {
        let d = size
        ZStack {
            // 外发光
            Circle()
                .fill(RadialGradient(
                    colors: [color.opacity(0.85), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: d * 0.72
                ))
                .frame(width: d * 1.7, height: d * 1.7)
                .blur(radius: 10)

            // 球体本体
            Circle()
                .fill(RadialGradient(
                    colors: [color, color.opacity(0.75)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: d
                ))
                .frame(width: d, height: d)
                .shadow(color: color.opacity(0.8), radius: d * 0.16)

            // 左上高光
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.65), Color.white.opacity(0.0)],
                    center: UnitPoint(x: 0.35, y: 0.28),
                    startRadius: 0,
                    endRadius: d * 0.6
                ))
                .frame(width: d * 0.82, height: d * 0.82)
                .blendMode(.screen)

            // 眼睛（跟随设置：开关/颜色）；stopped 是黑球，黑眼会不可见 → 用白眼
            let eyeFill = mood == "stopped" ? Color.white : settings.eyeColor.color
            if settings.showEyes {
                Ellipse()
                    .fill(eyeFill)
                    .frame(width: d * 0.10, height: d * 0.183)
                    .offset(x: -d * 0.117, y: 0)
                Ellipse()
                    .fill(eyeFill)
                    .frame(width: d * 0.10, height: d * 0.183)
                    .offset(x: d * 0.117, y: 0)
            }

            // stopped 是纯黑球，加一圈淡环便于辨认
            if mood == "stopped" {
                Circle()
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 2)
                    .frame(width: d + 6, height: d + 6)
            }
        }
        .frame(width: d * 2.0, height: d * 2.0)
    }
}
