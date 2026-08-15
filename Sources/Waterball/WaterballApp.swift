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

/// 菜单栏图标：状态色小球 + 两只竖向椭圆眼睛
struct MenuBarIcon: View {
    @ObservedObject private var model = WaterballModel.shared

    var body: some View {
        ZStack {
            Circle()
                .fill(model.color)

            HStack(spacing: 2.2) {
                Ellipse()
                    .fill(.white)
                    .frame(width: 1.4, height: 7.2)
                Ellipse()
                    .fill(.white)
                    .frame(width: 1.4, height: 7.2)
            }
        }
        .frame(width: 13, height: 13)
        .drawingGroup()
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

            Button("设置…") {
                // 通过通知路由到 AppDelegate，避免依赖 NSApp.delegate 类型
                NotificationCenter.default.post(name: .waterballToggleSettings, object: nil)
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}
