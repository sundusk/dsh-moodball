import AppKit
import SwiftUI
import Combine
import os

private let appLog = Logger(subsystem: "com.sundusk.moodball", category: "app")

/// 置顶悬浮窗：透明、无边框、不抢焦点、点击穿透。
/// 鼠标移入球体范围时恢复响应（可拖拽），移出后再次穿透。
/// 拖拽由 SwiftUI 手势驱动（见 MoodBallView），位置持久化到 UserDefaults。
final class MoodBallPanel: NSPanel {
    /// 供 SwiftUI 拖拽手势引用当前悬浮窗
    static weak var current: MoodBallPanel?

    /// 拖拽进行中（悬停检测据此保持响应，避免拖到一半变成点击穿透）
    var isDragging = false

    private enum PositionKeys {
        static let x = "moodball.ballPositionX"
        static let y = "moodball.ballPositionY"
        static let legacyX = "ballPositionX"
        static let legacyY = "ballPositionY"
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    /// 尝试恢复上次拖拽保存的位置；仅当设置允许且窗口中心仍在某个屏幕可视区内才生效
    @discardableResult
    func restoreSavedPosition() -> Bool {
        guard SettingsStore.shared.rememberPosition else { return false }
        let defaults = UserDefaults.standard
        let x = (defaults.object(forKey: PositionKeys.x) as? NSNumber
            ?? defaults.object(forKey: PositionKeys.legacyX) as? NSNumber)?.doubleValue
        let y = (defaults.object(forKey: PositionKeys.y) as? NSNumber
            ?? defaults.object(forKey: PositionKeys.legacyY) as? NSNumber)?.doubleValue
        guard let x, let y else { return false }
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
        UserDefaults.standard.set(Double(frame.origin.x), forKey: PositionKeys.x)
        UserDefaults.standard.set(Double(frame.origin.y), forKey: PositionKeys.y)
        appLog.info("persistPosition -> \(Int(self.frame.origin.x)),\(Int(self.frame.origin.y))")
    }
}

/// Separate control surface below the pet. Keeping it in its own panel means
/// expanding the composer never changes the pet window's drag anchor or size.
final class MoodBallComposerPanel: NSPanel {
    static weak var current: MoodBallComposerPanel?

    /// Prevent hover updates from snapping the panel back to its saved origin
    /// while the Mini drag gesture is moving it.
    var isMiniDragging = false
    /// Session-only Mini origin used when the user disables position saving.
    var transientMiniPosition: CGPoint?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MoodBallModel.shared
    private var panel: MoodBallPanel?
    private var composerPanel: MoodBallComposerPanel?
    private var settingsPanel: NSPanel?
    private var statePreviewPanel: NSPanel?
    private var hoverMonitors: [Any] = []
    private var visibilitySink: AnyCancellable?
    private var settingsSink: AnyCancellable?
    private var bubbleSink: AnyCancellable?
    private var composerSink: AnyCancellable?
    private var commandSink: AnyCancellable?
    private var hotKeySink: AnyCancellable?
    private var resignObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var statusSink: AnyCancellable?
    private var statusHeaderItem: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var togglePetMenuItem: NSMenuItem?
    private var shortcutMenuItems: [MoodBallShortcutAction: [NSMenuItem]] = [:]
    private var lastIconColor: Color?
    private let globalHotKeyManager = GlobalHotKeyManager()

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
        setupComposerPanel()
        setupGlobalHotKey()
        model.start()
        startHoverMonitor()
        observeVisibility()
        observeSettings()
        observeBubble()
        observeComposer()
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
        for monitor in hoverMonitors {
            NSEvent.removeMonitor(monitor)
        }
        hoverMonitors = []
        bubbleSink?.cancel()
        bubbleSink = nil
        statusSink?.cancel()
        statusSink = nil
        composerSink?.cancel()
        composerSink = nil
        commandSink?.cancel()
        commandSink = nil
        hotKeySink?.cancel()
        hotKeySink = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    // MARK: - 悬浮窗

    private func setupPanel() {
        let size = SettingsStore.shared.ballSize * 2.0
        let panel = MoodBallPanel(
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

        let hosting = NSHostingView(rootView: MoodBallView(model: model, settings: SettingsStore.shared))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        // 优先恢复上次拖拽位置，否则放屏幕右下角
        if !panel.restoreSavedPosition() {
            positionAtBottomRight(panel)
        }
        MoodBallPanel.current = panel
        if SettingsStore.shared.isBallVisible,
           SettingsStore.shared.displayMode == .petAndControls {
            panel.orderFrontRegardless()
        }
        self.panel = panel
    }

    private func setupComposerPanel() {
        let p = MoodBallComposerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 18),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.animationBehavior = .none
        p.isExcludedFromWindowsMenu = true
        p.contentView = NSHostingView(rootView: MoodBallComposerView(model: model, command: model.commandClient))
        self.composerPanel = p
        MoodBallComposerPanel.current = p
        updateComposerPanel()
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
        if isMiniMode {
            guard let composerPanel, composerPanel.isVisible else { return }
            let center = NSPoint(x: composerPanel.frame.midX, y: composerPanel.frame.midY)
            let centerOnScreen = NSScreen.screens.map(\.visibleFrame).contains { $0.contains(center) }
            if !centerOnScreen {
                positionAtBottomRight(composerPanel)
                let miniOrigin = Self.miniOrigin(for: composerPanel.frame)
                composerPanel.transientMiniPosition = miniOrigin
                if SettingsStore.shared.rememberPosition {
                    SettingsStore.shared.savedMiniPosition = miniOrigin
                }
            }
            return
        }
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
        if isMiniMode, let composerPanel {
            positionAtBottomRight(composerPanel)
            let miniOrigin = Self.miniOrigin(for: composerPanel.frame)
            composerPanel.transientMiniPosition = miniOrigin
            if SettingsStore.shared.rememberPosition {
                SettingsStore.shared.savedMiniPosition = miniOrigin
            }
            return
        }
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
                self.updateComposerPanel()
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
        let h = d * 2.0 + (showBubble ? MoodBallView.bubbleHeight : 0)
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
        // 事件驱动：鼠标移动/拖拽时才检测，鼠标不动时零唤醒（取代固定频率轮询定时器）。
        // 本地监视器：本 app 活跃时（拖拽中、设置面板开着）触发；
        // 全局监视器：其它 app 前台时触发（球默认点击穿透，鼠标事件不派发给本 app，
        //   只有全局监视器能看到光标移动）。
        // 全局监视器回调在后台线程，统一跳回主线程再更新。
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.updateHover()
            }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateHover()
            }
        }
        hoverMonitors = [local, global].compactMap { $0 }
    }

    private func updateHover() {
        let settings = SettingsStore.shared
        let isMini = settings.displayMode == .controlsOnly
        guard panel?.isVisible == true || (isMini && composerPanel?.isVisible == true) else { return }
        let mouse = NSEvent.mouseLocation
        let d = settings.ballSize
        let insideBall: Bool
        if let panel, panel.isVisible {
            let ballCenter = NSPoint(x: panel.frame.midX, y: panel.frame.minY + d)
            insideBall = hypot(mouse.x - ballCenter.x, mouse.y - ballCenter.y) <= d
        } else {
            insideBall = false
        }

        if settings.clickThroughMode != .always,
           model.composerPhase != .expanded {
            let controlFrame = composerPanel?.frame.insetBy(dx: -14, dy: -18)
            let bridgeFrame: NSRect?
            if let panel, panel.isVisible {
                let minX = min(panel.frame.minX, composerPanel?.frame.minX ?? panel.frame.minX) - 14
                let minY = min(panel.frame.minY, composerPanel?.frame.minY ?? panel.frame.minY) - 18
                bridgeFrame = NSRect(
                    x: minX,
                    y: minY,
                    width: max(panel.frame.maxX, composerPanel?.frame.maxX ?? panel.frame.maxX) - minX + 14,
                    height: max(panel.frame.maxY, composerPanel?.frame.maxY ?? panel.frame.maxY) - minY + 18
                )
            } else {
                bridgeFrame = nil
            }
            model.setComposerHovering(insideBall || controlFrame?.contains(mouse) == true || bridgeFrame?.contains(mouse) == true)
        }
        updateComposerPanel()

        guard let panel, panel.isVisible else { return }
        switch settings.clickThroughMode {
        case .always:
            // 永远穿透：常驻忽略鼠标事件（不可拖拽）
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
        case .never:
            // 永不穿透：常驻响应（无穿透）
            if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
        case .hover:
            // 悬停恢复：鼠标在球体圆形区域（球心距底边 = 球径）内时响应（可拖拽），否则穿透。
            // 面板在气泡出现时会向上增高，因此命中判定收窄到球体圆形，气泡区域保持点击穿透。
            let shouldIgnore = !panel.isDragging && !insideBall
            if panel.ignoresMouseEvents != shouldIgnore {
                panel.ignoresMouseEvents = shouldIgnore
                appLog.info("hover -> ignoresMouseEvents=\(shouldIgnore)")
            }
        }
    }

    // MARK: - 输入控件面板

    private func observeComposer() {
        composerSink = model.$composerPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateComposerPanel()
            }
        commandSink = model.commandClient.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateComposerPanel()
            }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.model.composerPhase == .expanded else { return }
                self.model.collapseComposer()
            }
        }
    }

    private func updateComposerPanel() {
        guard let composerPanel else { return }
        let settings = SettingsStore.shared
        guard settings.isBallVisible else {
            composerPanel.orderOut(nil)
            return
        }

        let size: NSSize
        if settings.displayMode == .controlsOnly {
            switch model.composerPhase {
            case .resting, .hovering:
                size = NSSize(width: 104, height: 34)
            case .expanded:
                size = NSSize(width: 340, height: 132)
            }
        } else {
            switch model.composerPhase {
            case .resting:
                size = NSSize(width: 72, height: 18)
            case .hovering:
                size = NSSize(width: 48, height: 34)
            case .expanded:
                size = NSSize(width: 340, height: 132)
            }
        }
        if !composerPanel.isMiniDragging {
            composerPanel.setFrame(composerFrame(size: size), display: true)
        }
        if model.composerPhase == .expanded {
            composerPanel.ignoresMouseEvents = false
        } else if isMiniMode {
            composerPanel.ignoresMouseEvents = settings.clickThroughMode == .always
        } else {
            composerPanel.ignoresMouseEvents = settings.clickThroughMode != .never
                && model.composerPhase != .hovering
        }
        composerPanel.orderFrontRegardless()
    }

    private var isMiniMode: Bool {
        SettingsStore.shared.displayMode == .controlsOnly
    }

    private func composerFrame(size: NSSize) -> NSRect {
        let settings = SettingsStore.shared
        if settings.displayMode == .controlsOnly,
           let saved = settings.rememberPosition
                ? settings.savedMiniPosition
                : composerPanel?.transientMiniPosition {
            let oldSize = NSSize(width: 104, height: 34)
            let center = NSPoint(x: saved.x + oldSize.width / 2, y: saved.y + oldSize.height / 2)
            return clampedComposerFrame(
                NSRect(
                    x: center.x - size.width / 2,
                    y: center.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
            )
        }
        guard let panel else { return NSRect(origin: .zero, size: size) }
        let centerX = panel.frame.midX
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(NSPoint(x: centerX, y: panel.frame.midY)) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // The composer belongs to the pet's bottom edge. Keep only a small
        // breathing gap so the hover affordance does not look detached.
        let petControlGap: CGFloat = 4
        let x = min(max(centerX - size.width / 2, visible.minX + petControlGap), visible.maxX - size.width - petControlGap)
        let belowY = panel.frame.minY - size.height - petControlGap
        let y: CGFloat
        if belowY >= visible.minY + petControlGap {
            y = belowY
        } else {
            // When there is no room below, sit above the visible pet (whose
            // sprite is bottom-anchored), not above the transparent hit area.
            y = min(
                panel.frame.minY + SettingsStore.shared.ballSize + petControlGap,
                visible.maxY - size.height - petControlGap
            )
        }
        return clampedComposerFrame(NSRect(x: x, y: y, width: size.width, height: size.height))
    }

    private static func miniOrigin(for frame: NSRect) -> CGPoint {
        let miniSize = NSSize(width: 104, height: 34)
        return CGPoint(
            x: frame.midX - miniSize.width / 2,
            y: frame.midY - miniSize.height / 2
        )
    }

    private func clampedComposerFrame(_ frame: NSRect) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(center) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return frame }
        let inset: CGFloat = 4
        let x = min(max(frame.minX, visible.minX + inset), max(visible.minX + inset, visible.maxX - frame.width - inset))
        let y = min(max(frame.minY, visible.minY + inset), max(visible.minY + inset, visible.maxY - frame.height - inset))
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    // MARK: - 菜单栏动作（通过 model.isBallVisible 驱动，避免依赖 NSApp.delegate 类型）

    private func observeVisibility() {
        visibilitySink = Publishers.CombineLatest(
            SettingsStore.shared.$isBallVisible,
            SettingsStore.shared.$displayMode
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] visible, displayMode in
                guard let self else { return }
                if visible, displayMode == .petAndControls {
                    if let panel = self.panel, !panel.isVisible {
                        panel.orderFrontRegardless()
                    }
                } else {
                    self.panel?.orderOut(nil)
                }
                self.updateComposerPanel()
                self.updateHover()
                appLog.info("display surfaces: visible=\(visible, privacy: .public) mode=\(displayMode.rawValue, privacy: .public)")
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

        // 菜单内容：状态行 + 显示/隐藏 + 设置… + 退出（与旧 MenuBarContent 一致）
        let menu = NSMenu()

        statusHeaderItem = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: "")
        statusHeaderItem?.isEnabled = false
        menu.addItem(statusHeaderItem!)

        menu.addItem(.separator())

        toggleMenuItem = makeShortcutMenuItem(
            action: .toggleBallVisibility,
            title: model.isBallVisible ? "隐藏全部" : "显示全部",
            selector: #selector(toggleBallVisibility)
        )
        menu.addItem(toggleMenuItem!)

        togglePetMenuItem = makeShortcutMenuItem(
            action: .togglePetVisibility,
            title: isMiniMode ? "显示桌宠形象" : "隐藏桌宠形象",
            selector: #selector(togglePetVisibility)
        )
        menu.addItem(togglePetMenuItem!)

        menu.addItem(makeShortcutMenuItem(
            action: .inputMessage,
            title: "输入消息",
            selector: #selector(inputMessageFromMenu)
        ))
        menu.addItem(makeShortcutMenuItem(
            action: .newSession,
            title: "新建会话",
            selector: #selector(newSessionFromMenu)
        ))
        menu.addItem(makeShortcutMenuItem(
            action: .selectWorkspace,
            title: "选择工作区",
            selector: #selector(selectWorkspaceFromMenu)
        ))
        menu.addItem(makeShortcutMenuItem(
            action: .openHarness,
            title: "打开 Harness",
            selector: #selector(openHarnessFromMenu)
        ))
        menu.addItem(makeShortcutMenuItem(
            action: .openSettings,
            title: "设置…",
            selector: #selector(toggleSettingsPanel)
        ))
        menu.addItem(makeShortcutMenuItem(
            action: .statePreview,
            title: "状态展示…",
            selector: #selector(toggleStatePreviewPanel)
        ))

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu

        // mood 颜色 / 球显隐 / 状态文案变化 → 刷新图标与菜单
        statusSink = Publishers.Merge(model.objectWillChange, SettingsStore.shared.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange 在属性写入前发出，推迟到下一轮再读，保证拿到新值
                Task { @MainActor [weak self] in
                    self?.refreshStatusItem()
                }
            }
        refreshStatusItem() // 初始绘制
    }

    /// 用最新状态刷新菜单栏图标与菜单文案。
    private func refreshStatusItem() {
        guard let item = statusItem else { return }
        let color = model.color

        // 颜色变化才重绘图片（轮询会高频触发 objectWillChange，避免每次都重建 NSImage）
        if lastIconColor != color {
            lastIconColor = color
            let image = Self.makeStatusIcon(color: color)
            item.button?.image = image
            item.button?.image?.isTemplate = false
            item.button?.imagePosition = .imageOnly
            statusHeaderItem?.image = Self.makeColoredDot(color: color, size: 10)
        }

        item.button?.toolTip = model.statusText
        item.button?.setAccessibilityLabel(model.statusText)
        statusHeaderItem?.title = model.statusText
        toggleMenuItem?.title = model.isBallVisible ? "隐藏全部" : "显示全部"
        togglePetMenuItem?.title = isMiniMode ? "显示桌宠形象" : "隐藏桌宠形象"
        applyMenuShortcuts()
    }

    private func makeShortcutMenuItem(
        action: MoodBallShortcutAction,
        title: String,
        selector: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        shortcutMenuItems[action, default: []].append(item)
        return item
    }

    private func applyMenuShortcuts() {
        let settings = SettingsStore.shared
        for action in MoodBallShortcutAction.allCases {
            let configuration = settings.shortcutConfiguration(for: action)
            let keyEquivalent = configuration.isEnabled && settings.shortcutConflict(for: action) == nil
                ? configuration.menuKeyEquivalent
                : nil
            let modifierMask = configuration.modifiers.intersection([.command, .option, .control, .shift])
            for item in shortcutMenuItems[action, default: []] {
                item.keyEquivalent = keyEquivalent ?? ""
                item.keyEquivalentModifierMask = keyEquivalent == nil ? [] : modifierMask
            }
        }
    }

    @objc private func toggleBallVisibility() {
        model.isBallVisible.toggle()
    }

    @objc private func togglePetVisibility() {
        SettingsStore.shared.displayMode = isMiniMode ? .petAndControls : .controlsOnly
    }

    // MARK: - 全局快捷键

    private func setupGlobalHotKey() {
        globalHotKeyManager.onTrigger = { [weak self] in
            Task { @MainActor [weak self] in
                self?.showComposerFromGlobalHotKey()
            }
        }
        hotKeySink = Publishers.CombineLatest3(
            SettingsStore.shared.$globalHotKeyEnabled,
            SettingsStore.shared.$globalHotKeyKeyCode,
            SettingsStore.shared.$globalHotKeyModifiers
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            self?.applyGlobalHotKeyConfiguration()
        }
        applyGlobalHotKeyConfiguration()
    }

    private func applyGlobalHotKeyConfiguration() {
        let settings = SettingsStore.shared
        let result = globalHotKeyManager.update(settings.globalHotKeyConfiguration)
        switch result {
        case .success:
            settings.setGlobalHotKeyStatus(nil)
        case .failure(let error):
            settings.setGlobalHotKeyStatus(error.localizedDescription + "；已保留上一次有效快捷键")
        }
    }

    private func showComposerFromGlobalHotKey() {
        // The shortcut remains useful after the user hides everything: reveal
        // the control surface, while respecting Mini mode's hidden pet.
        if !SettingsStore.shared.isBallVisible {
            SettingsStore.shared.isBallVisible = true
        }
        model.openComposer(focus: true)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, let composerPanel = self.composerPanel else { return }
            composerPanel.makeKeyAndOrderFront(nil)
        }
    }

    /// 自绘菜单栏图标：mood 颜色圆球 + 两只镂空小圆点眼睛（非模板图片）。
    /// `isTemplate = false`：不参与系统的模板染色，按原样显示。
    private static func makeStatusIcon(color: Color, size: CGFloat = 22) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath()
            // 圆球
            path.appendOval(in: rect.insetBy(dx: size * 0.08, dy: size * 0.08))
            // 两只镂空竖向椭圆眼睛：even-odd 填充把椭圆挖成透明
            let eyeW = size * 0.10
            let eyeH = size * 0.20
            let eyeGap = size * 0.16
            let eyeY = rect.midY - eyeH / 2
            path.appendOval(in: CGRect(x: rect.midX - eyeGap - eyeW / 2, y: eyeY, width: eyeW, height: eyeH))
            path.appendOval(in: CGRect(x: rect.midX + eyeGap - eyeW / 2, y: eyeY, width: eyeW, height: eyeH))
            path.windingRule = .evenOdd
            NSColor(color).setFill()
            path.fill()
            return true
        }
    }

    /// 菜单头部的状态色点：纯色实心圆，颜色跟随 mood。
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
        appMenu.addItem(withTitle: "关于 心情球", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(makeShortcutMenuItem(
            action: .inputMessage,
            title: "输入消息",
            selector: #selector(inputMessageFromMenu)
        ))
        appMenu.addItem(makeShortcutMenuItem(
            action: .newSession,
            title: "新建会话",
            selector: #selector(newSessionFromMenu)
        ))
        appMenu.addItem(makeShortcutMenuItem(
            action: .selectWorkspace,
            title: "选择工作区",
            selector: #selector(selectWorkspaceFromMenu)
        ))
        appMenu.addItem(makeShortcutMenuItem(
            action: .openHarness,
            title: "打开 Harness",
            selector: #selector(openHarnessFromMenu)
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(makeShortcutMenuItem(
            action: .openSettings,
            title: "设置…",
            selector: #selector(toggleSettingsPanel)
        ))
        appMenu.addItem(makeShortcutMenuItem(
            action: .statePreview,
            title: "状态展示…",
            selector: #selector(toggleStatePreviewPanel)
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 心情球", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        applyMenuShortcuts()
    }

    // MARK: - Harness 输入入口

    @objc private func inputMessageFromMenu() {
        showComposerFromGlobalHotKey()
    }

    @objc private func newSessionFromMenu() {
        model.startNewSession()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func selectWorkspaceFromMenu() {
        model.openComposer()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHarnessFromMenu() {
        model.openHarness()
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
            p.title = "心情球设置"
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

    // MARK: - 状态展示面板（选状态看球，方便截图）

    @objc func toggleStatePreviewPanel() {
        if let statePreviewPanel, statePreviewPanel.isVisible {
            statePreviewPanel.orderOut(nil)
            return
        }
        // 与其他面板互斥
        if let settingsPanel, settingsPanel.isVisible { settingsPanel.orderOut(nil) }
        openStatePreviewPanel()
    }

    private func openStatePreviewPanel() {
        let panel: NSPanel
        if let existing = statePreviewPanel {
            panel = existing
        } else {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            p.title = "心情球状态展示"
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: StatePreviewPanelView())
            p.center()
            statePreviewPanel = p
            panel = p
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        appLog.info("state preview panel opened")
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
