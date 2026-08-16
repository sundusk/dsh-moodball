import SwiftUI

/// 球上快捷控制面板：单击小球弹出，快速调整大小 / 发光 / 气泡文字 / 锁定位置 / 显隐。
/// 完整设置仍可进「设置…」面板。
struct QuickControlView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var model = MoodBallModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("心情球")
                    .font(.headline)
                Spacer()
                Text("\(Int(settings.ballSize)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // 大小
            HStack(spacing: 8) {
                Text("大小")
                    .font(.callout)
                Slider(value: $settings.ballSize, in: 60...200, step: 4)
            }

            Toggle("发光", isOn: $settings.glowEnabled)
            Toggle("气泡文字", isOn: $settings.showStatusBubble)
            Toggle("锁定位置", isOn: $settings.lockPosition)
            Toggle("显示悬浮球", isOn: $model.isBallVisible)

            Divider()

            Text("拖动小球可移动位置；锁定后仅可点击")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 230)
    }
}
