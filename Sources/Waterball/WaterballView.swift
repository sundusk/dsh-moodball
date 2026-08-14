import SwiftUI

/// 发光小球：radialGradient 本体 + blur 外发光 + 高光，
/// 用 TimelineView 按 mood 周期做正弦呼吸（透明度 + 缩放，ease-in-out 平滑）。
struct WaterballView: View {
    @ObservedObject var model: WaterballModel

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
    }
}
