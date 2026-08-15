import SwiftUI

/// 设置面板：外观 / 颜色 / 行为 三个 Tab，顶部带实时预览小球。
struct SettingsPanelView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var tab: Tab = .appearance

    enum Tab: String, CaseIterable, Identifiable {
        case appearance = "外观"
        case colors = "颜色"
        case behavior = "行为"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部实时预览（跟随当前设置的渲染）
            PreviewBall(settings: settings)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.05))

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                switch tab {
                case .appearance: AppearanceTab(settings: settings)
                case .colors: ColorsTab(settings: settings)
                case .behavior: BehaviorTab(settings: settings)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 420, height: 520)
    }
}

// MARK: - 实时预览

/// 预览用的小球：复用呼吸渲染（静止在一个相位，跟随设置的大小/颜色/速度）
private struct PreviewBall: View {
    @ObservedObject var settings: SettingsStore
    @State private var phase = false

    var body: some View {
        let d = settings.ballSize
        // 预览小球固定为青色 RGB(0,255,255)（不跟随状态色）
        let color = Color(hex: 0x00FFFF)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color, color.opacity(0.75)], center: .topLeading, startRadius: 0, endRadius: d))
                .frame(width: d, height: d)
                .shadow(color: color.opacity(0.8), radius: d * 0.16)
            // 眼睛：与主球一致（竖椭圆），跟随「显示眼睛」设置与眼睛颜色；带眨眼动画
            if settings.showEyes {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let eyeScale = WaterballView.blinkScale(at: timeline.date.timeIntervalSinceReferenceDate)
                    ZStack {
                        Ellipse()
                            .fill(settings.eyeColor.color)
                            .frame(width: d * 0.10, height: d * 0.183)
                            .offset(x: -d * 0.117, y: 0)
                            .scaleEffect(x: 1, y: eyeScale, anchor: .center)
                        Ellipse()
                            .fill(settings.eyeColor.color)
                            .frame(width: d * 0.10, height: d * 0.183)
                            .offset(x: d * 0.117, y: 0)
                            .scaleEffect(x: 1, y: eyeScale, anchor: .center)
                    }
                }
            }
            // 高光
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0)], center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: d * 0.6))
                .frame(width: d * 0.82, height: d * 0.82)
                .blendMode(.screen)
        }
        .scaleEffect(phase ? 1.05 : 0.95)
        .opacity(phase ? 1.0 : 0.6)
        .animation(.easeInOut(duration: settings.breathingSpeed).repeatForever(autoreverses: true), value: phase)
        .onAppear { phase = true }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 外观

private struct AppearanceTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("球体大小") {
                HStack {
                    Slider(value: Binding(
                        get: { settings.ballSize },
                        set: { settings.ballSize = $0 }
                    ), in: 60...200, step: 4)
                    Text("\(Int(settings.ballSize)) px")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("呼吸速度") {
                HStack {
                    Slider(value: Binding(
                        get: { settings.breathingSpeed },
                        set: { settings.breathingSpeed = $0 }
                    ), in: 0.5...5, step: 0.1)
                    Text(String(format: "%.1fs", settings.breathingSpeed))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
            Text("周期越短呼吸越快。全局统一速度。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("显示眼睛", isOn: Binding(
                get: { settings.showEyes },
                set: { settings.showEyes = $0 }
            ))

            LabeledContent("眼睛颜色") {
                Picker("", selection: Binding(
                    get: { settings.eyeColor },
                    set: { settings.eyeColor = $0 }
                )) {
                    ForEach(EyeColor.allCases) { color in
                        Text(color.label).tag(color)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Toggle("显示气泡文字", isOn: Binding(
                get: { settings.showStatusBubble },
                set: { settings.showStatusBubble = $0 }
            ))
            Text("非空闲状态时在球上方显示漫画风状态提醒（正在思考中/工具调用…），空闲自动隐藏。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("重置位置到右下角") {
                NotificationCenter.default.post(name: .waterballResetPosition, object: nil)
            }

            Divider()
            Text("提示：直接拖动桌面上的球即可移动它，位置会被记住。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 颜色

private struct ColorsTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("球始终跟随 DeepSeek 状态变色；下面的颜色可在契约基础上自定义。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            ForEach(moodColorConfigs, id: \.mood) { cfg in
                HStack {
                    Text(cfg.label)
                        .frame(width: 64, alignment: .leading)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { settings.moodColors[cfg.mood] ?? Color(hex: cfg.defaultHex) },
                        set: { settings.setMoodColor(cfg.mood, $0) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Text(hexString(settings.moodColors[cfg.mood] ?? Color(hex: cfg.defaultHex)))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            }

            Divider().padding(.vertical, 4)

            HStack {
                Text("未连接灰")
                    .frame(width: 64, alignment: .leading)
                Spacer()
                ColorPicker("", selection: $settings.disconnectedColor, supportsOpacity: false)
                    .labelsHidden()
            }

            Button("恢复默认颜色") {
                settings.resetMoodColors()
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    private func hexString(_ color: Color) -> String {
        String(format: "#%06X", colorToHex(color))
    }
}

// MARK: - 行为

private struct BehaviorTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("API 地址") {
                TextField("http://127.0.0.1:3080", text: Binding(
                    get: { settings.apiBase },
                    set: { settings.apiBase = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }

            LabeledContent("轮询间隔") {
                HStack {
                    Slider(value: Binding(
                        get: { settings.pollInterval },
                        set: { settings.pollInterval = $0 }
                    ), in: 0.3...5, step: 0.1)
                    Text(String(format: "%.1fs", settings.pollInterval))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("请求超时") {
                HStack {
                    Slider(value: Binding(
                        get: { settings.requestTimeout },
                        set: { settings.requestTimeout = $0 }
                    ), in: 0.5...5, step: 0.5)
                    Text(String(format: "%.1fs", settings.requestTimeout))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("点击穿透") {
                Picker("", selection: Binding(
                    get: { settings.clickThroughMode },
                    set: { settings.clickThroughMode = $0 }
                )) {
                    ForEach(ClickThroughMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            Toggle("记住拖拽位置（重启恢复）", isOn: Binding(
                get: { settings.rememberPosition },
                set: { settings.rememberPosition = $0 }
            ))

            Divider()
            Text("修改 API 地址或轮询间隔会立即生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
