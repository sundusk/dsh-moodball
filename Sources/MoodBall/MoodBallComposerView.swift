import AppKit
import SwiftUI

/// The three visual states beneath the pet: a quiet bar, a hover affordance,
/// and the expanded native composer. The task cards deliberately stay in this
/// same surface so the former bell popover does not become a second list UI.
struct MoodBallComposerView: View {
    @ObservedObject var model: MoodBallModel
    @ObservedObject var command: MoodBallCommandClient
    @ObservedObject private var settings = SettingsStore.shared

    @State private var miniGrabOffset: CGSize = .zero
    @State private var hasMiniGrabOffset = false

    static let taskSurfaceWidth: CGFloat = 320
    static let taskBarHeight: CGFloat = 34
    static let taskCardHeight: CGFloat = 58
    static let expandedHeightWithoutAttachments: CGFloat = 154
    static let expandedHeightWithAttachments: CGFloat = 226

    var body: some View {
        if model.composerPhase == .expanded {
            expandedComposer
        } else if settings.displayMode == .controlsOnly {
            taskSurface(isMini: true)
        } else {
            standardComposer
        }
    }

    @ViewBuilder
    private var standardComposer: some View {
        switch model.composerPhase {
        case .resting:
            Capsule(style: .continuous)
                .fill(.white.opacity(0.46))
                .frame(width: 42, height: 5)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .hovering:
            taskSurface(isMini: false)
        case .expanded:
            expandedComposer
        }
    }

    private var hasTaskCards: Bool {
        command.taskListAvailable && !command.currentWorkspaceTasks.isEmpty
    }

    private var orderedTasks: [MoodBallTaskSummary] {
        command.sortedTasks
    }

    private var taskSurfaceHeight: CGFloat {
        guard hasTaskCards else { return Self.taskBarHeight + 8 }
        if command.focusedTask != nil { return 166 }
        let count = model.taskListExpanded ? min(orderedTasks.count, 4) : 1
        return 8 + Self.taskBarHeight + 7
            + CGFloat(count) * Self.taskCardHeight
            + CGFloat(max(0, count - 1)) * 7
    }

    private var taskSurfaceWidth: CGFloat {
        hasTaskCards ? Self.taskSurfaceWidth : 120
    }

    private func taskSurface(isMini: Bool) -> some View {
        VStack(spacing: 7) {
            taskActionBar(isMini: isMini)

            if hasTaskCards {
                if let task = command.focusedTask {
                    taskDetailCard(task)
                } else if model.taskListExpanded {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 7) {
                            ForEach(orderedTasks) { task in
                                taskCard(task)
                            }
                        }
                        .background(HiddenVerticalScroller())
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: Self.taskCardHeight * 4 + 21)
                } else if let task = orderedTasks.first {
                    ZStack {
                        if orderedTasks.count > 1 {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(.regularMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .stroke(.white.opacity(0.16), lineWidth: 0.8)
                                )
                                .padding(.horizontal, 5)
                                .offset(y: -4)
                        }
                        taskCard(task)
                    }
                    .frame(height: Self.taskCardHeight)
                }
            }
        }
        .padding(.horizontal, hasTaskCards ? 4 : 0)
        .padding(.vertical, 4)
        .frame(width: taskSurfaceWidth, height: taskSurfaceHeight, alignment: .top)
    }

    private func taskActionBar(isMini: Bool) -> some View {
        HStack(spacing: 5) {
            if isMini {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 26)
                    .contentShape(Rectangle())
                    .gesture(miniDragGesture)
                    .accessibilityLabel("拖动 Mini 控件")
            }

            Button {
                model.openComposer(focus: false)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(width: 32, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("输入消息")

            if command.taskListAvailable && !command.currentWorkspaceTasks.isEmpty {
                Divider()
                    .frame(height: 16)
                    .opacity(0.45)

                Button {
                    if command.focusedTask == nil, let first = orderedTasks.first {
                        model.focusTask(first.id)
                    } else {
                        model.clearFocusedTask()
                    }
                } label: {
                    Image(systemName: command.unreadTaskCount > 0 ? "bell.badge.fill" : "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(command.unreadTaskCount > 0 ? Color.orange : .primary.opacity(0.72))
                        .frame(width: 32, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("任务提醒，\(command.currentWorkspaceTasks.count)项")

                if command.currentWorkspaceTasks.count > 1 {
                    Button {
                        model.toggleTaskList()
                    } label: {
                        Image(systemName: model.taskListExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.72))
                            .frame(width: 24, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.taskListExpanded ? "收起任务列表" : "展开任务列表")
                }
            }
        }
        .padding(.horizontal, isMini ? 6 : 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .frame(height: Self.taskBarHeight)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func taskCard(_ task: MoodBallTaskSummary) -> some View {
        Button {
            model.focusTask(task.id)
        } label: {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(task.statusLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 3)
                taskStatusIcon(task)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: Self.taskCardHeight, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(command.isTaskUnread(task) ? Color.orange.opacity(0.7) : .white.opacity(0.18), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title)，\(task.statusLabel)")
    }

    @ViewBuilder
    private func taskStatusIcon(_ task: MoodBallTaskSummary) -> some View {
        if task.taskRunning || task.running {
            ProgressView()
                .controlSize(.small)
                .tint(.accentColor)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: task.statusIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(task.failed ? Color.red : task.completed ? Color.green : .secondary)
                .frame(width: 22, height: 22)
        }
    }

    private func taskDetailCard(_ task: MoodBallTaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Button {
                    model.clearFocusedTask()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("返回任务列表")

                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 2)
                taskStatusIcon(task)
            }

            HStack(spacing: 5) {
                Text(task.statusLabel)
                    .font(.system(size: 10, weight: .medium))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("更新于")
                    .font(.system(size: 10))
                Text(Date(timeIntervalSince1970: task.updatedAt / 1000), style: .relative)
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)

            if let warning = command.continuationWarning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button("继续此会话") {
                    if model.continueTask(task) {
                        model.openComposer(focus: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(task.sessionID, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("复制会话 ID")

                Button("打开 Harness") {
                    model.openHarness()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.8)
        )
    }

    private var miniDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard settings.clickThroughMode != .always,
                      let panel = MoodBallComposerPanel.current else { return }
                let mouse = NSEvent.mouseLocation
                if !hasMiniGrabOffset {
                    panel.isMiniDragging = true
                    miniGrabOffset = CGSize(
                        width: mouse.x - panel.frame.origin.x,
                        height: mouse.y - panel.frame.origin.y
                    )
                    hasMiniGrabOffset = true
                }
                panel.setFrameOrigin(NSPoint(
                    x: mouse.x - miniGrabOffset.width,
                    y: mouse.y - miniGrabOffset.height
                ))
            }
            .onEnded { _ in
                if let panel = MoodBallComposerPanel.current, hasMiniGrabOffset {
                    let frame = panel.frame
                    let position = CGPoint(x: frame.minX, y: frame.minY)
                    panel.transientMiniPosition = position
                    if settings.rememberPosition {
                        settings.savedMiniPosition = position
                    }
                    panel.isMiniDragging = false
                }
                hasMiniGrabOffset = false
                miniGrabOffset = .zero
            }
    }

    private var expandedComposer: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Menu {
                    if command.workspaces.isEmpty {
                        Text("请先在 Harness 中添加工作区")
                    } else {
                        ForEach(command.workspaces) { workspace in
                            Button {
                                command.selectWorkspace(workspace.id)
                            } label: {
                                if workspace.id == command.selectedWorkspaceID {
                                    Label(workspace.title, systemImage: "checkmark")
                                } else {
                                    Text(workspace.title)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("刷新工作区") { command.refreshWorkspaces() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                        Text(command.selectedWorkspaceTitle ?? "选择工作区")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.78))
                }
                .menuStyle(.borderlessButton)
                .disabled(command.submissionStatus == .submitting)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                if let sessionID = command.sessionID {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sessionID, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("复制会话 ID")
                }

                Button {
                    model.collapseComposer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("收起输入框")
            }

            Text("输入目标 · \(command.inputTargetTitle)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !command.draftImages.isEmpty {
                attachmentRail
            }

            HStack(alignment: .bottom, spacing: 7) {
                ZStack(alignment: .topLeading) {
                    if command.draft.isEmpty {
                        Text(command.hasWorkspace ? "输入消息…" : "请先选择工作区")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary.opacity(0.75))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                    }
                    MoodBallTextView(
                        text: $command.draft,
                        onSubmit: { model.submitDraft() },
                        onEscape: { model.collapseComposer() },
                        onPasteImage: { command.addImageFromPasteboard($0) },
                        focusRequest: model.composerFocusRequest
                    )
                }
                .frame(minHeight: 44, maxHeight: 104)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.white.opacity(0.23), lineWidth: 0.8)
                )

                Menu {
                    Button("粘贴剪贴板图片", systemImage: "doc.on.clipboard") {
                        model.pasteImage()
                    }
                    Button("框选截图", systemImage: "viewfinder") {
                        model.captureRegion()
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 31)
                }
                .menuStyle(.borderlessButton)
                .disabled(!command.imageAttachmentsAvailable || command.submissionStatus == .submitting)
                .help(command.imageAttachmentsAvailable
                    ? (command.attachmentLimitSummary ?? "添加图片")
                    : "当前插件不支持图片附件")

                Button {
                    model.submitDraft()
                } label: {
                    if command.submissionStatus == .submitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .frame(width: 31, height: 31)
                .background(command.canSend ? Color.accentColor : Color.secondary.opacity(0.35), in: Circle())
                .disabled(!command.canSend)
                .accessibilityLabel("发送")
            }

            if command.connection != .connected || !command.capabilitiesAvailable {
                Text("输入服务未连接，请确认新版 MoodBall 插件已加载")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if command.workspaces.isEmpty {
                Text("没有可用工作区，请先在 Harness 中添加")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let label = command.submissionStatus.label ?? command.lastError {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(command.submissionStatus == .submitted ? .green : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 0.8)
        )
        .frame(
            width: 340,
            height: command.draftImages.isEmpty
                ? Self.expandedHeightWithoutAttachments
                : Self.expandedHeightWithAttachments
        )
    }

    private var attachmentRail: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(command.draftImages) { image in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let preview = NSImage(contentsOf: image.fileURL) {
                                Image(nsImage: preview)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(image.error == nil ? .white.opacity(0.2) : Color.red, lineWidth: 1)
                        )

                        Button {
                            command.removeDraftImage(image.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.72))
                        }
                        .buttonStyle(.plain)
                        .disabled(command.submissionStatus == .submitting)
                        .offset(x: 5, y: -5)
                        .accessibilityLabel("移除 \(image.name)")
                    }
                    .help(image.error ?? "\(image.name) · \(ByteCountFormatter.string(fromByteCount: Int64(image.bytes), countStyle: .file))")
                }

                if command.draftImages.contains(where: { $0.error != nil }) {
                    Button {
                        command.retryFailedImages()
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.automatic)
        .frame(height: 60)
        .accessibilityLabel("待发送图片，\(command.draftImages.count) 张")
    }
}

/// SwiftUI's scroll-indicator visibility can still inherit macOS's “Always”
/// scrollbar preference inside a transparent panel. Disable only the backing
/// AppKit scroller; wheel and trackpad scrolling continue to work normally.
private struct HiddenVerticalScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HiddenVerticalScrollerView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? HiddenVerticalScrollerView)?.hideEnclosingScroller()
    }
}

private final class HiddenVerticalScrollerView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        hideEnclosingScroller()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideEnclosingScroller()
    }

    override func layout() {
        super.layout()
        hideEnclosingScroller()
    }

    func hideEnclosingScroller() {
        guard let scrollView = enclosingScrollView else { return }
        if scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = false
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
        }
        scrollView.verticalScroller?.isHidden = true
    }
}

/// NSTextView keeps IME composition separate from submit: Enter confirms a
/// composed Chinese candidate first, while Shift+Enter remains a newline.
struct MoodBallTextView: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onPasteImage: (NSPasteboard) -> Void
    let focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let textView = MoodBallPasteTextView()
        textView.onPasteImage = { pasteboard in context.coordinator.parent.onPasteImage(pasteboard) }
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 7)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView

        DispatchQueue.main.async {
            scroll.window?.makeFirstResponder(textView)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        context.coordinator.parent = self
        (textView as? MoodBallPasteTextView)?.onPasteImage = { pasteboard in
            context.coordinator.parent.onPasteImage(pasteboard)
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                scroll.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MoodBallTextView
        var lastFocusRequest: Int?

        init(_ parent: MoodBallTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                if textView.hasMarkedText() { return false }
                if NSEvent.modifierFlags.contains(.shift) { return false }
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
}

final class MoodBallPasteTextView: NSTextView {
    var onPasteImage: ((NSPasteboard) -> Void)?

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if NSImage(pasteboard: pasteboard) != nil {
            onPasteImage?(pasteboard)
            return
        }
        super.paste(sender)
    }
}
