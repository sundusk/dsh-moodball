import AppKit
import SwiftUI
import Combine
import os

private let appLog = Logger(subsystem: "com.linxin666.waterball-mac", category: "app")

/// 置顶悬浮窗：透明、无边框、不抢焦点、点击穿透。
/// 鼠标移入球体范围时恢复响应（可拖拽），移出后再次穿透。
final class WaterballPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = WaterballModel.shared
    private var panel: WaterballPanel?
    private var hoverTimer: Timer?
    private var visibilitySink: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 纯菜单栏应用：不占 Dock
        NSApp.setActivationPolicy(.accessory)

        setupPanel()
        model.start()
        startHoverMonitor()
        observeVisibility()
        // 显示器增删/分辨率变化时，把球收回可视区（避免被 macOS 甩到屏幕外）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        appLog.info("didFinishLaunching done")
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    // MARK: - 悬浮窗

    private func setupPanel() {
        let size = model.ballSize * 2.0
        let panel = WaterballPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating                       // 置顶
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true      // 可拖拽
        panel.ignoresMouseEvents = true               // 默认点击穿透
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true

        let hosting = NSHostingView(rootView: WaterballView(model: model))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        positionAtBottomRight(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func positionAtBottomRight(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else { return }
        let inset: CGFloat = 16
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - panel.frame.width - inset,
            y: screen.visibleFrame.minY + inset
        )
        panel.setFrameOrigin(origin)
        appLog.info("positionAtBottomRight -> \(Int(origin.x)),\(Int(origin.y)) on visibleFrame \(Int(screen.visibleFrame.minX)),\(Int(screen.visibleFrame.minY)) \(Int(screen.visibleFrame.width))x\(Int(screen.visibleFrame.height))")
    }

    @objc private func screenParametersChanged() {
        guard let panel, panel.isVisible else { return }
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let onScreen = visibleFrames.contains { $0.intersects(panel.frame) }
        if !onScreen {
            positionAtBottomRight(panel)
        }
    }

    // MARK: - 悬停检测（穿透 ↔ 可拖拽）

    private func startHoverMonitor() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateHover()
            }
        }
    }

    private func updateHover() {
        guard let panel, panel.isVisible else { return }
        // NSEvent.mouseLocation 与 window.frame 都是「左下原点」的全局屏幕坐标，可直接比较
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        let shouldIgnore = !inside
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }

    // MARK: - 菜单栏动作（通过 model.isBallVisible 驱动，避免依赖 NSApp.delegate 类型）

    private func observeVisibility() {
        visibilitySink = model.$isBallVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                guard let self, let panel = self.panel else { return }
                if visible {
                    if !panel.isVisible {
                        self.positionAtBottomRight(panel)
                        panel.orderFrontRegardless()
                    }
                } else if panel.isVisible {
                    panel.orderOut(nil)
                }
                appLog.info("visibility sink: visible=\(visible, privacy: .public) panelIsVisible=\(panel.isVisible, privacy: .public)")
            }
    }
}
