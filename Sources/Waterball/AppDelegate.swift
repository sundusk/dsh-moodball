import AppKit
import SwiftUI
import Combine
import os

private let appLog = Logger(subsystem: "com.linxin666.waterball-mac", category: "app")

/// 置顶悬浮窗：透明、无边框、不抢焦点、点击穿透。
/// 鼠标移入球体范围时恢复响应（可拖拽），移出后再次穿透。
/// 拖拽由 SwiftUI 手势驱动（见 WaterballView），位置持久化到 UserDefaults。
final class WaterballPanel: NSPanel {
    /// 供 SwiftUI 拖拽手势引用当前悬浮窗
    static weak var current: WaterballPanel?

    /// 拖拽进行中（悬停检测据此保持响应，避免拖到一半变成点击穿透）
    var isDragging = false

    private enum PositionKeys {
        static let x = "ballPositionX"
        static let y = "ballPositionY"
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    /// 尝试恢复上次拖拽保存的位置；仅当设置允许且窗口中心仍在某个屏幕可视区内才生效
    @discardableResult
    func restoreSavedPosition() -> Bool {
        guard SettingsStore.shared.rememberPosition else { return false }
        let defaults = UserDefaults.standard
        guard let x = defaults.object(forKey: PositionKeys.x) as? CGFloat,
              let y = defaults.object(forKey: PositionKeys.y) as? CGFloat else { return false }
        // 用「窗口中心」判断而非整窗相交：避免显示器变化后只留一截在屏边、球心在屏外
        let center = NSPoint(x: x + self.frame.width / 2, y: y + self.frame.height / 2)
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        guard visibleFrames.contains(where: { $0.contains(center) }) else { return false }
        setFrameOrigin(NSPoint(x: x, y: y))
        return true
    }

    /// 拖拽结束时保存当前位置（受「记住位置」设置控制）
    func persistPosition() {
        guard SettingsStore.shared.rememberPosition else { return }
        UserDefaults.standard.set(frame.origin.x, forKey: PositionKeys.x)
        UserDefaults.standard.set(frame.origin.y, forKey: PositionKeys.y)
        appLog.info("persistPosition -> \(Int(self.frame.origin.x)),\(Int(self.frame.origin.y))")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = WaterballModel.shared
    private var panel: WaterballPanel?
    private var settingsPanel: NSPanel?
    private var hoverTimer: Timer?
    private var visibilitySink: AnyCancellable?
    private var settingsSink: AnyCancellable?
    private var bubbleSink: AnyCancellable?
    private var statusItem: NSStatusItem?
    private var statusSink: AnyCancellable?
    private var statusHeaderItem: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var lastIconColor: Color?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例守卫：若已有同 Bundle ID 的实例在运行，本实例立即退出。
        // （从 Spotlight/访达重复点击，或从不同路径副本启动时，防止出现多个悬浮球）
        if Self.hasExistingInstance() {
            appLog.info("detected existing instance, quitting")
            NSApp.terminate(nil)
            return
        }

        // 纯菜单栏应用：不占 Dock
        NSApp.setActivationPolicy(.accessory)

        // 菜单栏彩色图标（NSStatusItem 非模板渲染）+ 标准主菜单
        setupStatusItem()
        setupMainMenu()

        setupPanel()
        model.start()
        startHoverMonitor()
        observeVisibility()
        observeSettings()
        observeBubble()
        // 显示器增删/分辨率变化时，把球收回可视区（避免被 macOS 甩到屏幕外）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // 设置面板「重置位置」请求
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resetPositionRequested),
            name: .waterballResetPosition,
            object: nil
        )
        // 菜单栏「设置…」请求
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleSettingsPanelNotification),
            name: .waterballToggleSettings,
            object: nil
        )
        appLog.info("didFinishLaunching done")
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        hoverTimer?.invalidate()
        hoverTimer = nil
        bubbleSink?.cancel()
        bubbleSink = nil
        statusSink?.cancel()
        statusSink = nil
    }

    // MARK: - 悬浮窗

    private func setupPanel() {
        let size = SettingsStore.shared.ballSize * 2.0
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
        panel.ignoresMouseEvents = true               // 默认点击穿透（悬停时由 updateHover 恢复响应）
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true

        let hosting = NSHostingView(rootView: WaterballView(model: model, settings: SettingsStore.shared))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        // 优先恢复上次拖拽位置，否则放屏幕右下角
        if !panel.restoreSavedPosition() {
            positionAtBottomRight(panel)
        }
        WaterballPanel.current = panel
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
        // 显示器增删/分辨率变化后，若窗口中心不在任何屏幕的可视区内
        // （可能只留一截在屏边、球心已甩到无屏幕区域，导致拖不到），
        // 就把球收回鼠标所在屏的右下角。
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let centerOnScreen = visibleFrames.contains { $0.contains(center) }
        if !centerOnScreen {
            positionAtBottomRight(panel)
            appLog.info("screen changed: ball center off-screen, repositioned to bottom-right")
        }
    }

    @objc private func resetPositionRequested() {
        guard let panel else { return }
        positionAtBottomRight(panel)
    }

    @objc private func toggleSettingsPanelNotification() {
        toggleSettingsPanel()
    }

    // MARK: - 设置联动

    private func observeSettings() {
        // 球大小变化 → 保持球心不动地调整窗口尺寸（含气泡增高）
        settingsSink = SettingsStore.shared.$ballSize
            .receive(on: RunLoop.main)
            .sink { [weak self] newSize in
                guard let self, let panel = self.panel else { return }
                let showBubble = self.showStatusBubble
                panel.setFrame(self.panelFrame(ballSize: newSize, showBubble: showBubble), display: true)
                appLog.info("ballSize changed -> \(Int(newSize))")
            }
    }

    // MARK: - 状态气泡（面板增高联动）

    /// 当前是否显示状态气泡（mood 非空闲且设置开关打开）
    private var showStatusBubble: Bool {
        model.bubbleText != nil && SettingsStore.shared.showStatusBubble
    }

    /// 依据球大小与气泡显隐计算面板 frame：保持球心（水平中心、距底边 = 球径）屏幕位置不变。
    private func panelFrame(ballSize d: CGFloat, showBubble: Bool) -> NSRect {
        let w = d * 2.0
        let h = d * 2.0 + (showBubble ? WaterballView.bubbleHeight : 0)
        let old = panel?.frame ?? NSRect(x: 0, y: 0, width: w, height: h)
        let ballCenterX = old.midX
        let ballCenterY = old.minY + old.width / 2 // 球心距底边 = 旧球径
        return NSRect(x: ballCenterX - w / 2, y: ballCenterY - d, width: w, height: h)
    }

    private func observeBubble() {
        // mood 变化（气泡显隐）或设置开关变化 → 增高/缩回面板顶部
        let moodChanges: AnyPublisher<Void, Never> = model.$mood
            .map { _ in () as Void }
            .eraseToAnyPublisher()
        let bubbleSetting: AnyPublisher<Void, Never> = SettingsStore.shared.$showStatusBubble
            .map { _ in () as Void }
            .eraseToAnyPublisher()
        bubbleSink = Publishers.MergeMany(moodChanges, bubbleSetting)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel else { return }
                let showBubble = self.showStatusBubble
                let frame = self.panelFrame(ballSize: SettingsStore.shared.ballSize, showBubble: showBubble)
                if !frame.equalTo(panel.frame) {
                    panel.setFrame(frame, display: true)
                    appLog.info("panel frame -> \(Int(frame.width))x\(Int(frame.height)) bubble=\(showBubble)")
                }
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
        switch SettingsStore.shared.clickThroughMode {
        case .always:
            // 永远穿透：常驻忽略鼠标事件（不可拖拽）
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
        case .never:
            // 永不穿透：常驻响应（无穿透）
            if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
        case .hover:
            // 悬停恢复：鼠标在球体圆形区域（球心距底边 = 球径）内时响应（可拖拽），否则穿透。
            // 面板在气泡出现时会向上增高，因此命中判定收窄到球体圆形，气泡区域保持点击穿透。
            let mouse = NSEvent.mouseLocation
            let d = SettingsStore.shared.ballSize
            let ballCenter = NSPoint(x: panel.frame.midX, y: panel.frame.minY + d)
            let inside = hypot(mouse.x - ballCenter.x, mouse.y - ballCenter.y) <= d
            let shouldIgnore = !panel.isDragging && !inside
            if panel.ignoresMouseEvents != shouldIgnore {
                panel.ignoresMouseEvents = shouldIgnore
                appLog.info("hover -> ignoresMouseEvents=\(shouldIgnore)")
            }
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
                        panel.orderFrontRegardless() // 恢复显示时回到上次拖拽的位置，不重置
                    }
                } else if panel.isVisible {
                    panel.orderOut(nil)
                }
                appLog.info("visibility sink: visible=\(visible, privacy: .public) panelIsVisible=\(panel.isVisible, privacy: .public)")
            }
    }

    // MARK: - 菜单栏图标（NSStatusItem，非模板彩色渲染）

    /// 创建菜单栏常驻图标。
    /// 注意：SwiftUI 的 `MenuBarExtra` 会把 label 强制渲染成单色模板图片，
    /// mood 颜色会丢失（看起来就是个黑点/白点），所以这里改用 AppKit 的
    /// `NSStatusItem` + 自绘非模板图片，让圆球真正显示 mood 颜色。
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        // 图标：纯黑圆球 + 镂空圆点眼睛（静态，不随 mood 变色）
        let icon = Self.makeStatusIcon()
        item.button?.image = icon
        item.button?.image?.isTemplate = false
        item.button?.imagePosition = .imageOnly

        // 菜单内容：状态行 + 显示/隐藏 + 设置… + 退出（与旧 MenuBarContent 一致）
        let menu = NSMenu()

        statusHeaderItem = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: "")
        statusHeaderItem?.isEnabled = false
        menu.addItem(statusHeaderItem!)

        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(
            title: model.isBallVisible ? "隐藏悬浮球" : "显示悬浮球",
            action: #selector(toggleBallVisibility),
            keyEquivalent: ""
        )
        toggleMenuItem?.target = self
        menu.addItem(toggleMenuItem!)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(toggleSettingsPanel), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu

        // mood 颜色 / 球显隐 / 状态文案变化 → 刷新图标与菜单
        statusSink = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange 在属性写入前发出，推迟到下一轮再读，保证拿到新值
                Task { @MainActor [weak self] in
                    self?.refreshStatusItem()
                }
            }
        refreshStatusItem() // 初始绘制
    }

    /// 用最新状态刷新菜单栏菜单文案与菜单头部色点。
    private func refreshStatusItem() {
        guard let item = statusItem else { return }
        let color = model.color

        // 菜单头部的状态色点：颜色变化才重绘（轮询会高频触发 objectWillChange，避免每次都重建 NSImage）
        if lastIconColor != color {
            lastIconColor = color
            statusHeaderItem?.image = Self.makeColoredDot(color: color, size: 10)
        }

        item.button?.toolTip = model.statusText
        item.button?.setAccessibilityLabel(model.statusText)
        statusHeaderItem?.title = model.statusText
        toggleMenuItem?.title = model.isBallVisible ? "隐藏悬浮球" : "显示悬浮球"
    }

    @objc private func toggleBallVisibility() {
        model.isBallVisible.toggle()
    }

    /// 自绘菜单栏图标：纯黑圆球 + 两只镂空小圆点眼睛（非模板图片）。
    /// `isTemplate = false`：不参与系统的模板染色，按原样显示。
    private static func makeStatusIcon(size: CGFloat = 16) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath()
            // 圆球（比旧版大一圈）
            path.appendOval(in: rect.insetBy(dx: size * 0.08, dy: size * 0.08))
            // 两只镂空小圆点眼睛：even-odd 填充把圆点挖成透明
            let eyeR = size * 0.105
            let eyeGap = size * 0.21
            let eyeY = rect.midY
            path.appendOval(in: CGRect(x: rect.midX - eyeGap - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2))
            path.appendOval(in: CGRect(x: rect.midX + eyeGap - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2))
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
    }

    /// 菜单头部的状态色点：纯色实心圆，颜色跟随 mood（菜单栏图标本体已固定为黑色）。
    private static func makeColoredDot(color: Color, size: CGFloat = 10) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: size * 0.12, dy: size * 0.12)).fill()
            return true
        }
    }

    // MARK: - 主菜单（手动补齐，替代 SwiftUI 自动生成的菜单）

    /// 无 SwiftUI App 场景后手动建立标准主菜单：
    /// 保证「设置…（⌘,）」与文本输入框的剪切/复制/粘贴等快捷键可用。
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 水球", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "设置…", action: #selector(toggleSettingsPanel), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 水球", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 设置面板

    /// 打开/关闭设置面板（菜单栏「设置…」）
    @objc func toggleSettingsPanel() {
        if let settingsPanel, settingsPanel.isVisible {
            settingsPanel.orderOut(nil)
            return
        }
        openSettingsPanel()
    }

    private func openSettingsPanel() {
        let panel: NSPanel
        if let existing = settingsPanel {
            panel = existing
        } else {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            p.title = "水球设置"
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: SettingsPanelView())
            p.center()
            settingsPanel = p
            panel = p
        }
        // 设置面板需要能输入（TextField 等），临时激活本 app
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        appLog.info("settings panel opened")
    }

    /// 是否已有同 Bundle ID 的其它实例在运行（用于单实例守卫）。
    /// 找到任一其它实例即返回 true。
    static func hasExistingInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ownPID }
        return !others.isEmpty
    }
}
