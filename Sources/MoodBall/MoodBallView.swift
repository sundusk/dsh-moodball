import SwiftUI

/// 发光小球：radialGradient 本体 + blur 外发光 + 高光，
/// 用 TimelineView 按 mood 周期做正弦呼吸（透明度 + 缩放，ease-in-out 平滑）。
/// 附带拖拽手势：按住球体任意位置即可把整个悬浮窗拖到任何地方（位置会记住）。
/// 非空闲状态时，在球脑门上方显示漫画风说话气泡（中文状态提醒），空闲时隐藏。
/// 布局采用「球体底部锚定」：气泡出现时面板向上增高 bubbleHeight，球心距底边恒为
/// ballSize，因此球的屏幕位置在气泡显隐切换时保持不变。
struct MoodBallView: View {
    @ObservedObject var model: MoodBallModel
    @ObservedObject private var settings: SettingsStore

    init(model: MoodBallModel, settings: SettingsStore) {
        self.model = model
        self.settings = settings
    }

    /// 按下时鼠标与窗口原点的偏移（全局坐标），拖拽中保持不变
    @State private var grabOffset: CGSize = .zero
    @State private var hasGrabOffset = false
    /// 拖拽按下时的鼠标全局坐标（用于区分「单击」与「拖动」）
    @State private var dragStart: CGPoint?
    /// 上次单击时间（用于识别双击 → 兴奋晃动）
    @State private var lastTapAt: Date?

    /// 状态气泡总高度（正文 30 + 尾巴 14），气泡出现时面板额外增高的量。
    /// AppDelegate 同步用它计算面板高度。
    static let bubbleHeight: CGFloat = 44
    /// 气泡尾巴尖端与球头顶部的间距
    static let tailGap: CGFloat = 4

    var body: some View {
        let d = model.ballSize
        let showBubble = model.bubbleText != nil && settings.showStatusBubble

        ZStack(alignment: .top) {
            // —— 球体层：底部锚定（偏移 bubbleHeight），命中区收窄到球体圆形 ——
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let wave = (sin(t * 2.0 * .pi / model.breathingPeriod) + 1.0) / 2.0 // 0...1
                let scale = 0.90 + 0.14 * wave
                let opacity = 0.55 + 0.45 * wave
                // 眨眼：每 4 秒眨一次，闭眼 0.12s（快）+ 睁眼 0.18s（慢），其余时间全睁
                let eyeScale = Self.blinkScale(at: t)
                // 双击兴奋摇动：触发后 2s 内绕底部支点缓慢左右摇动（钟摆式，约 1Hz），幅度线性衰减
                let wiggleStart = model.wiggleTriggeredAt?.timeIntervalSinceReferenceDate
                let wiggleTime = wiggleStart.map { t - $0 } ?? 2.0
                let wiggling = wiggleTime < 2.0
                let wiggleAngle = wiggling
                    ? sin(wiggleTime * 2.0 * .pi * 1.0) * (1.0 - wiggleTime / 2.0) * 0.35
                    : 0

                ZStack {
                    // 外发光（可在快捷控制/设置面板里关闭）
                    if settings.glowEnabled {
                        Circle()
                            .fill(RadialGradient(
                                colors: [model.color.opacity(0.85), model.color.opacity(0.0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: d * 0.72
                            ))
                            .frame(width: d * 1.7, height: d * 1.7)
                            .blur(radius: 10)
                    }

                    // 球体本体
                    Circle()
                        .fill(RadialGradient(
                            colors: [model.color, model.color.opacity(0.75)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: d
                        ))
                        .frame(width: d, height: d)
                        .shadow(color: settings.glowEnabled ? model.color.opacity(0.8) : .clear, radius: d * 0.16)

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

                    // 眼睛：两个竖椭圆（与网页版心情球一致的比例，120 viewBox 下 cx=46/74, rx=6, ry=11）
                    // 可在设置面板「外观」里关闭，颜色可切黑白；带眨眼动画（竖向缩放）
                    if settings.showEyes {
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

                    // stopped 是纯黑球，在深色壁纸上几乎不可见 → 加一圈淡环便于辨认
                    if model.mood == "stopped" {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.30), lineWidth: 2)
                            .frame(width: d + 6, height: d + 6)
                    }
                }
                .scaleEffect(scale)
                .opacity(opacity)
                .rotationEffect(.radians(wiggleAngle), anchor: .bottom)
                .frame(width: d * 2.0, height: d * 2.0)
            }
            .frame(width: d * 2.0, height: d * 2.0)
            .contentShape(Circle()) // 只在球体/光晕圆形区域内响应拖拽，四个角不挡操作
            .offset(y: showBubble ? Self.bubbleHeight : 0)
            .gesture(dragGesture)

            // —— 状态气泡层：仅动画自身显隐，不影响布局（面板高度由外层瞬时切换）——
            ZStack(alignment: .top) {
                if showBubble, let text = model.bubbleText {
                    SpeechBubble(text: text, color: model.color)
                        .offset(y: d / 2 - Self.tailGap)
                        .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showBubble)
            .allowsHitTesting(false)
        }
        .frame(width: d * 2.0, height: d * 2.0 + (showBubble ? Self.bubbleHeight : 0))
    }

    /// 眨眼竖向缩放：周期 4s，闭眼 0.12s（快）+ 睁眼 0.18s（慢），其余全睁（1.0）。
    /// 返回 0.08...1.0 的竖向缩放值，越小眼睛越「闭」。
    static func blinkScale(at t: TimeInterval) -> CGFloat {
        let period: TimeInterval = 4.0
        let closeDur: TimeInterval = 0.12
        let openDur: TimeInterval = 0.18
        let phase = t.truncatingRemainder(dividingBy: period)
        if phase < closeDur {
            // 闭眼：从 1 → 0.08（线性，快）
            return CGFloat(1.0 - phase / closeDur * 0.92)
        }
        if phase < closeDur + openDur {
            // 睁眼：从 0.08 → 1（线性，稍慢）
            let p = (phase - closeDur) / openDur
            return CGFloat(0.08 + p * 0.92)
        }
        return 1.0
    }

    /// 拖拽：让窗口跟随鼠标的全局位置（抓取点保持在光标下），
    /// 不依赖手势 translation，避免窗口移动后坐标系反馈导致拖拽缩水。
    /// 单击无操作；双击触发兴奋晃动；锁定位置时不可拖拽。
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard let panel = MoodBallPanel.current else { return }
                panel.isDragging = true
                let mouse = NSEvent.mouseLocation // 全局坐标（左下原点），与 frame.origin 同坐标系
                if !hasGrabOffset {
                    grabOffset = CGSize(
                        width: mouse.x - panel.frame.origin.x,
                        height: mouse.y - panel.frame.origin.y
                    )
                    dragStart = mouse
                    hasGrabOffset = true
                }
                // 锁定位置：不移动窗口（仍允许单击弹出快捷控制）
                if settings.lockPosition { return }
                panel.setFrameOrigin(NSPoint(
                    x: mouse.x - grabOffset.width,
                    y: mouse.y - grabOffset.height
                ))
            }
            .onEnded { _ in
                guard let panel = MoodBallPanel.current else {
                    dragStart = nil
                    hasGrabOffset = false
                    grabOffset = .zero
                    return
                }
                let mouse = NSEvent.mouseLocation
                // 几乎没移动 → 单击：切换球上快捷控制面板
                let isTap: Bool
                if let start = dragStart {
                    isTap = hypot(mouse.x - start.x, mouse.y - start.y) < 4
                } else {
                    isTap = false
                }
                if isTap {
                    // 双击（0.35s 内两次单击）→ 兴奋晃动；单击无操作
                    let now = Date()
                    if let last = lastTapAt, now.timeIntervalSince(last) < 0.35 {
                        lastTapAt = nil
                        model.triggerWiggle()
                    } else {
                        lastTapAt = now
                    }
                    dragStart = nil
                    hasGrabOffset = false
                    grabOffset = .zero
                    panel.isDragging = false
                    return
                }
                if settings.lockPosition {
                    dragStart = nil
                    hasGrabOffset = false
                    grabOffset = .zero
                    panel.isDragging = false
                    return
                }
                // 抬手时把抓取点精确归位到光标下，消除事件延迟造成的残差
                if hasGrabOffset {
                    panel.setFrameOrigin(NSPoint(
                        x: mouse.x - grabOffset.width,
                        y: mouse.y - grabOffset.height
                    ))
                }
                dragStart = nil
                hasGrabOffset = false
                grabOffset = .zero
                panel.isDragging = false
                panel.persistPosition()
            }
    }
}

// MARK: - 状态气泡（漫画风说话框）

/// 漫画风说话气泡：圆角矩形白底 + 状态色描边 + 底部小三角尾巴指向球脑门。
struct SpeechBubble: View {
    let text: String
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.8))
                .lineLimit(1)
                .frame(height: 30)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(color, lineWidth: 2)
                )
            BubbleTail(color: color)
                .frame(width: 16, height: 14)
        }
        .fixedSize()
    }
}

/// 气泡尾巴：白色小三角 + 两侧状态色描边（顶部与圆角矩形下缘相接，不封口）。
struct BubbleTail: View {
    let color: Color

    var body: some View {
        Triangle()
            .fill(.white.opacity(0.92))
            .overlay(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 8, y: 14))
                    p.addLine(to: CGPoint(x: 16, y: 0))
                }
                .stroke(color, lineWidth: 2)
            )
    }
}

/// 倒三角（尖端朝下）。
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
