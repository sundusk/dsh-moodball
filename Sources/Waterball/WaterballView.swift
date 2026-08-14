import SwiftUI

/// 发光小球：radialGradient 本体 + blur 外发光 + 高光，
/// 用 TimelineView 按 mood 周期做正弦呼吸（透明度 + 缩放，ease-in-out 平滑）。
/// 附带拖拽手势：按住球体任意位置即可把整个悬浮窗拖到任何地方（位置会记住）。
struct WaterballView: View {
    @ObservedObject var model: WaterballModel
    /// 按下时鼠标与窗口原点的偏移（全局坐标），拖拽中保持不变
    @State private var grabOffset: CGSize = .zero
    @State private var hasGrabOffset = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let wave = (sin(t * 2.0 * .pi / model.breathingPeriod) + 1.0) / 2.0 // 0...1
            let scale = 0.90 + 0.14 * wave
            let opacity = 0.55 + 0.45 * wave
            let d = model.ballSize

            ZStack {
                // 外发光
                Circle()
                    .fill(RadialGradient(
                        colors: [model.color.opacity(0.85), model.color.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: d * 0.72
                    ))
                    .frame(width: d * 1.7, height: d * 1.7)
                    .blur(radius: 10)

                // 球体本体
                Circle()
                    .fill(RadialGradient(
                        colors: [model.color, model.color.opacity(0.75)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: d
                    ))
                    .frame(width: d, height: d)
                    .shadow(color: model.color.opacity(0.8), radius: d * 0.16)

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

                // 眼睛：两个竖椭圆（与网页版水球一致的比例，120 viewBox 下 cx=46/74, rx=6, ry=11）
                // 可在设置面板「外观」里关闭，颜色可切黑白
                if SettingsStore.shared.showEyes {
                    Ellipse()
                        .fill(SettingsStore.shared.eyeColor.color)
                        .frame(width: d * 0.10, height: d * 0.183)
                        .offset(x: -d * 0.117, y: 0)
                    Ellipse()
                        .fill(SettingsStore.shared.eyeColor.color)
                        .frame(width: d * 0.10, height: d * 0.183)
                        .offset(x: d * 0.117, y: 0)
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
            .frame(width: d * 2.0, height: d * 2.0)
        }
        .frame(width: model.ballSize * 2.0, height: model.ballSize * 2.0)
        .allowsHitTesting(true)
        .contentShape(Circle()) // 只在球体/光晕圆形区域内响应拖拽，四个角不挡操作
        .gesture(dragGesture)
    }

    /// 拖拽：让窗口跟随鼠标的全局位置（抓取点保持在光标下），
    /// 不依赖手势 translation，避免窗口移动后坐标系反馈导致拖拽缩水。
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard let panel = WaterballPanel.current else { return }
                panel.isDragging = true
                let mouse = NSEvent.mouseLocation // 全局坐标（左下原点），与 frame.origin 同坐标系
                if !hasGrabOffset {
                    grabOffset = CGSize(
                        width: mouse.x - panel.frame.origin.x,
                        height: mouse.y - panel.frame.origin.y
                    )
                    hasGrabOffset = true
                }
                panel.setFrameOrigin(NSPoint(
                    x: mouse.x - grabOffset.width,
                    y: mouse.y - grabOffset.height
                ))
            }
            .onEnded { _ in
                guard let panel = WaterballPanel.current else {
                    hasGrabOffset = false
                    grabOffset = .zero
                    return
                }
                // 抬手时把抓取点精确归位到光标下，消除事件延迟造成的残差
                if hasGrabOffset {
                    let mouse = NSEvent.mouseLocation
                    panel.setFrameOrigin(NSPoint(
                        x: mouse.x - grabOffset.width,
                        y: mouse.y - grabOffset.height
                    ))
                }
                hasGrabOffset = false
                grabOffset = .zero
                panel.isDragging = false
                panel.persistPosition()
            }
    }
}
