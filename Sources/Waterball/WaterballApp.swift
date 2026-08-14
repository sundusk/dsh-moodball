import SwiftUI
import AppKit

@main
struct WaterballApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.menu)
    }
}

/// 菜单栏图标：实心圆点，颜色跟随 mood
struct MenuBarIcon: View {
    @ObservedObject private var model = WaterballModel.shared

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(model.color)
            .accessibilityLabel(model.statusText)
    }
}

/// 菜单内容：当前状态 + 显示/隐藏 + 退出
struct MenuBarContent: View {
    @ObservedObject private var model = WaterballModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.color)
                    .frame(width: 10, height: 10)
                Text(model.statusText)
                    .font(.system(size: 13))
            }
            .padding(.vertical, 2)

            Divider()

            // 标题随当前状态切换：显示中 →「隐藏悬浮球」，隐藏中 →「显示悬浮球」
            Button(model.isBallVisible ? "隐藏悬浮球" : "显示悬浮球") {
                model.isBallVisible.toggle()
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}
