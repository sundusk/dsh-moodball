import AppKit
import SwiftUI

/// The three visual states beneath the pet: a quiet bar, a hover affordance,
/// and the expanded native composer.
struct MoodBallComposerView: View {
    @ObservedObject var model: MoodBallModel
    @ObservedObject var command: MoodBallCommandClient
    @ObservedObject private var settings = SettingsStore.shared

    @State private var miniGrabOffset: CGSize = .zero
    @State private var hasMiniGrabOffset = false

    var body: some View {
        if settings.displayMode == .controlsOnly && model.composerPhase != .expanded {
            miniControlBar
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
            Button {
                model.openComposer()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 34, height: 30)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("输入消息")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .expanded:
            expandedComposer
        }
    }

    private var miniControlBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
                .gesture(miniDragGesture)
                .accessibilityLabel("拖动 Mini 控件")

            Button {
                model.openComposer(focus: true)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(width: 32, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("输入消息")
        }
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .frame(width: 104, height: 34)
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
                        focusRequest: model.composerFocusRequest
                    )
                }
                .frame(minHeight: 44, maxHeight: 104)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.white.opacity(0.23), lineWidth: 0.8)
                )

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
            } else if let label = command.submissionStatus.label {
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
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        .frame(width: 340, height: 132)
    }
}

/// NSTextView keeps IME composition separate from submit: Enter confirms a
/// composed Chinese candidate first, while Shift+Enter remains a newline.
struct MoodBallTextView: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let textView = NSTextView()
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
