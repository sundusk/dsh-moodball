import Foundation
import AppKit
import Network
import SwiftUI

enum MoodBallCommandConnection: Equatable {
    case disconnected
    case connecting
    case connected
}

struct MoodBallWorkspace: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let path: String
    let status: String
    let sessionIds: [String]
}

struct MoodBallImageLimits: Codable, Equatable {
    let maxImageBytes: Int
    let maxImagesPerMessage: Int
    let maxMessageImageBytes: Int
    let mediaTypes: [String]
}

struct MoodBallDraftImage: Codable, Equatable, Identifiable {
    let id: String
    let path: String
    let mediaType: String
    let name: String
    let bytes: Int
    var error: String?

    var fileURL: URL { URL(fileURLWithPath: path) }
}

enum MoodBallSubmissionStatus: Equatable {
    case idle
    case submitting
    case submitted
    case unconfirmed
    case failed(String)

    var label: String? {
        switch self {
        case .idle: return nil
        case .submitting: return "正在提交…"
        case .submitted: return "已提交"
        case .unconfirmed: return "提交结果未确认"
        case .failed(let message): return message
        }
    }
}

enum MoodBallCommandError: LocalizedError {
    case unavailable
    case timedOut
    case malformed
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "发送服务未连接，请确认 MoodBall 插件已加载"
        case .timedOut: return "提交结果未确认"
        case .malformed: return "MoodBall 插件返回了无法识别的结果"
        case .server(_, let message): return message
        }
    }
}

/// MoodBall-only client for the plugin's user-local command socket.
@MainActor
final class MoodBallCommandClient: ObservableObject {
    @Published private(set) var connection: MoodBallCommandConnection = .disconnected
    @Published private(set) var capabilitiesAvailable = false
    @Published private(set) var taskListAvailable = false
    @Published private(set) var imageAttachmentsAvailable = false
    @Published private(set) var imageLimits: MoodBallImageLimits?
    @Published private(set) var workspaces: [MoodBallWorkspace] = []
    @Published private(set) var tasks: [MoodBallTaskSummary] = []
    @Published private(set) var selectedWorkspaceID: String?
    @Published private(set) var sessionID: String?
    @Published private(set) var sessionSnapshot: MoodBridgeSnapshot?
    @Published private(set) var focusedTaskID: String?
    @Published private(set) var submissionStatus: MoodBallSubmissionStatus = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var continuationWarning: String?
    @Published private(set) var draftImages: [MoodBallDraftImage] = []
    @Published var draft: String {
        didSet { defaults.set(draft, forKey: Keys.draft) }
    }

    var onAccepted: (() -> Void)?

    private enum Keys {
        static let workspaceID = "moodball.command.workspaceID"
        static let sessionID = "moodball.command.sessionID"
        static let draft = "moodball.command.draft"
        static let requestID = "moodball.command.pendingRequestID"
        static let requestText = "moodball.command.pendingRequestText"
        static let taskReadMarkers = "moodball.command.taskReadMarkers"
        static let draftImages = "moodball.command.draftImages"
        static let requestSignature = "moodball.command.pendingRequestSignature"
    }

    private struct TaskReadMarker: Codable {
        let updatedAt: TimeInterval
        let mood: String
    }

    private let defaults: UserDefaults
    private let socketPath: String
    private let queue = DispatchQueue(label: "com.sundusk.moodball.command-client")
    private var connectionHandle: NWConnection?
    private var receiveBuffer = Data()
    private var queuedPayloads: [Data] = []
    private var pending: [String: (Result<[String: Any], Error>) -> Void] = [:]
    private var started = false
    private var pendingRequestID: String?
    private var pendingRequestText: String?
    private var pendingRequestSignature: String?
    private var reconnectTask: Task<Void, Never>?
    private var readMarkers: [String: TaskReadMarker] = [:]
    private var hasReceivedTaskBaseline = false

    init(defaults: UserDefaults = .standard, socketPath: String = MoodBallCommandClient.defaultSocketPath) {
        self.defaults = defaults
        self.socketPath = socketPath
        selectedWorkspaceID = defaults.string(forKey: Keys.workspaceID)
        sessionID = defaults.string(forKey: Keys.sessionID)
        draft = defaults.string(forKey: Keys.draft) ?? ""
        pendingRequestID = defaults.string(forKey: Keys.requestID)
        pendingRequestText = defaults.string(forKey: Keys.requestText)
        pendingRequestSignature = defaults.string(forKey: Keys.requestSignature)
        if let data = defaults.data(forKey: Keys.draftImages),
           let decoded = try? JSONDecoder().decode([MoodBallDraftImage].self, from: data) {
            draftImages = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
            persistDraftImages()
        }
        if let data = defaults.data(forKey: Keys.taskReadMarkers),
           let markers = try? JSONDecoder().decode([String: TaskReadMarker].self, from: data) {
            readMarkers = markers
        }
    }

    nonisolated static var defaultSocketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/MoodBall/moodball-command.sock"
    }

    var selectedWorkspace: MoodBallWorkspace? {
        guard let selectedWorkspaceID else { return nil }
        return workspaces.first { $0.id == selectedWorkspaceID }
    }

    var selectedWorkspaceTitle: String? { selectedWorkspace?.title }

    var hasWorkspace: Bool { selectedWorkspace != nil }

    var currentWorkspaceTasks: [MoodBallTaskSummary] {
        guard let selectedWorkspaceID else { return [] }
        return tasks.filter { $0.workspaceID == selectedWorkspaceID }
    }

    /// Task-center order: waiting for a user action, unread failures, unread
    /// completions, running work, then the remaining recent Sessions.
    var sortedTasks: [MoodBallTaskSummary] {
        currentWorkspaceTasks.sorted { left, right in
            let leftRank = taskRank(left)
            let rightRank = taskRank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    var focusedTask: MoodBallTaskSummary? {
        guard let focusedTaskID else { return nil }
        return tasks.first { $0.id == focusedTaskID }
    }

    var unreadTaskCount: Int {
        currentWorkspaceTasks.reduce(into: 0) { count, task in
            if isTaskUnread(task) { count += 1 }
        }
    }

    var inputTargetTitle: String {
        guard let sessionID else { return "新建会话" }
        return tasks.first { $0.id == sessionID }?.title ?? "会话 \(sessionID.suffix(8))"
    }

    var canSend: Bool {
        guard connection == .connected,
              capabilitiesAvailable,
              hasWorkspace,
              (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftImages.isEmpty),
              submissionStatus != .submitting else { return false }
        if !draftImages.isEmpty && !imageAttachmentsAvailable { return false }
        return !(sessionSnapshot?.taskRunning ?? false)
    }

    var attachmentLimitSummary: String? {
        guard let imageLimits else { return nil }
        return "最多 \(imageLimits.maxImagesPerMessage) 张，单张 \(Self.byteLabel(imageLimits.maxImageBytes))"
    }

    var busyMessage: String? {
        guard let snapshot = sessionSnapshot, snapshot.taskRunning else { return nil }
        if snapshot.waitingForUser { return "请在 Harness 中完成当前操作" }
        return "当前会话正在执行，请稍候"
    }

    func start() {
        guard !started else { return }
        started = true
        connect()
    }

    func stop() {
        started = false
        connectionHandle?.cancel()
        connectionHandle = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        queuedPayloads.removeAll(keepingCapacity: false)
        receiveBuffer.removeAll(keepingCapacity: false)
        failPending(with: MoodBallCommandError.unavailable)
        connection = .disconnected
        capabilitiesAvailable = false
        taskListAvailable = false
        imageAttachmentsAvailable = false
        imageLimits = nil
    }

    func addImageFromPasteboard(_ pasteboard: NSPasteboard = .general) {
        guard submissionStatus != .submitting else { return }
        guard imageAttachmentsAvailable else {
            lastError = "当前 MoodBall 插件不支持图片附件"
            return
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            lastError = "剪贴板中没有可用图片"
            return
        }
        addDraftImage(data: png, mediaType: "image/png", name: "粘贴图片.png")
    }

    func makeRegionCaptureURL() -> URL? {
        guard submissionStatus != .submitting else { return nil }
        guard imageAttachmentsAvailable else {
            lastError = "当前 MoodBall 插件不支持图片附件"
            return nil
        }
        do {
            let directory = try draftImageDirectory()
            return directory.appendingPathComponent("截屏-\(UUID().uuidString.lowercased()).png")
        } catch {
            lastError = errorMessage(error)
            return nil
        }
    }

    func acceptRegionCapture(at url: URL) {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        addDraftImageFile(url: url, data: data, mediaType: "image/png", name: "框选截图.png")
    }

    func cancelRegionCapture(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func reportRegionCaptureFailure(_ message: String) {
        lastError = message.isEmpty ? "截图失败，请检查屏幕录制权限" : message
    }

    func removeDraftImage(_ id: String) {
        guard submissionStatus != .submitting else { return }
        guard let image = draftImages.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: image.fileURL)
        draftImages.removeAll { $0.id == id }
        invalidatePendingSubmission()
        persistDraftImages()
    }

    func retryFailedImages() {
        for index in draftImages.indices { draftImages[index].error = nil }
        persistDraftImages()
        submitDraft()
    }

    func refreshWorkspaces() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await request(action: "workspaces")
                let decoded = decodeWorkspaces(response["workspaces"])
                workspaces = decoded
                if let selectedWorkspaceID, decoded.contains(where: { $0.id == selectedWorkspaceID }) {
                    return
                }
                if decoded.count == 1, let only = decoded.first {
                    selectWorkspace(only.id)
                } else {
                    selectedWorkspaceID = nil
                    defaults.removeObject(forKey: Keys.workspaceID)
                }
            } catch {
                record(error)
            }
        }
    }

    func selectWorkspace(_ id: String) {
        guard submissionStatus != .submitting else { return }
        guard workspaces.contains(where: { $0.id == id }) else { return }
        if selectedWorkspaceID != id {
            selectedWorkspaceID = id
            defaults.set(id, forKey: Keys.workspaceID)
            clearSessionBinding()
            focusedTaskID = nil
        }
    }

    /// Forget only MoodBall's current binding. Existing Harness sessions are
    /// never deleted or cancelled.
    func startNewSession() {
        guard submissionStatus != .submitting else { return }
        clearSessionBinding()
        focusedTaskID = nil
        submissionStatus = .idle
        lastError = nil
        continuationWarning = nil
    }

    func focusTask(_ id: String) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        focusedTaskID = id
        markTaskRead(task)
        continuationWarning = nil
    }

    func clearFocusedTask() {
        focusedTaskID = nil
        continuationWarning = nil
    }

    /// Select a task as the input target. A non-empty draft blocks switching
    /// to another Session so a pending message cannot be sent elsewhere.
    @discardableResult
    func continueTask(_ task: MoodBallTaskSummary) -> Bool {
        guard submissionStatus != .submitting else { return false }
        guard task.workspaceID == selectedWorkspaceID else { return false }
        if (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftImages.isEmpty),
           sessionID != task.sessionID {
            continuationWarning = "请先处理当前草稿，再切换会话"
            return false
        }
        continuationWarning = nil
        focusedTaskID = task.id
        markTaskRead(task)
        if sessionID == task.sessionID { return true }

        sessionID = task.sessionID
        defaults.set(task.sessionID, forKey: Keys.sessionID)
        // Task summaries retain terminal results for card history. The pet must
        // wait for the live Session subscription instead of animating that
        // historical result indefinitely.
        sessionSnapshot = nil
        subscribe(to: task.sessionID)
        return true
    }

    func refreshTasks() {
        guard taskListAvailable else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await request(action: "tasks", timeout: 12)
                applyTasks(response["tasks"])
            } catch {
                record(error)
            }
        }
    }

    func submitDraft() {
        guard submissionStatus != .submitting else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draftImages.isEmpty else { return }
        guard selectedWorkspace != nil else {
            submissionStatus = .failed("请先选择工作区")
            return
        }
        if let busyMessage {
            submissionStatus = .failed(busyMessage)
            return
        }

        let signature = submissionSignature(text: text)
        let submittedImages = draftImages
        let submittedImageIDs = Set(submittedImages.map(\.id))
        let requestID: String
        if pendingRequestSignature == signature, let pendingRequestID {
            requestID = pendingRequestID
        } else {
            requestID = "moodball-\(UUID().uuidString.lowercased())"
            pendingRequestID = requestID
            pendingRequestText = text
            pendingRequestSignature = signature
            defaults.set(requestID, forKey: Keys.requestID)
            defaults.set(text, forKey: Keys.requestText)
            defaults.set(signature, forKey: Keys.requestSignature)
        }

        submissionStatus = .submitting
        lastError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let encodedImages = try encodedDraftImages(submittedImages)
                let sessionID = try await ensureSession()
                let workspaceID = try requireWorkspaceID()
                let response = try await request(
                    action: "prompt",
                    fields: [
                        "workspaceId": workspaceID,
                        "sessionId": sessionID,
                        "requestId": requestID,
                        "text": text,
                        "images": encodedImages,
                    ],
                    timeout: 32
                )
                guard response["ok"] as? Bool != false,
                      response["accepted"] as? Bool == true else {
                    throw MoodBallCommandError.malformed
                }
                if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
                clearDraftImages(ids: submittedImageIDs)
                pendingRequestID = nil
                pendingRequestText = nil
                pendingRequestSignature = nil
                defaults.removeObject(forKey: Keys.requestID)
                defaults.removeObject(forKey: Keys.requestText)
                defaults.removeObject(forKey: Keys.requestSignature)
                submissionStatus = .submitted
                if let task = tasks.first(where: { $0.id == sessionID }) { markTaskRead(task) }
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draftImages.isEmpty {
                    onAccepted?()
                }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if submissionStatus == .submitted { submissionStatus = .idle }
            } catch {
                if case MoodBallCommandError.timedOut = error {
                    submissionStatus = .unconfirmed
                } else {
                    submissionStatus = .failed(errorMessage(error))
                }
                lastError = errorMessage(error)
                if !draftImages.isEmpty {
                    let message = errorMessage(error)
                    for index in draftImages.indices where submittedImageIDs.contains(draftImages[index].id) {
                        draftImages[index].error = message
                    }
                    persistDraftImages()
                }
            }
        }
    }

    private func ensureSession() async throws -> String {
        let workspaceID = try requireWorkspaceID()
        let session = sessionID ?? "moodball-session-\(UUID().uuidString.lowercased())"
        if sessionID == nil {
            sessionID = session
            defaults.set(session, forKey: Keys.sessionID)
        }
        let response = try await request(
            action: "createSession",
            fields: ["workspaceId": workspaceID, "sessionId": session],
            timeout: 12
        )
        guard let returnedSession = response["sessionId"] as? String, !returnedSession.isEmpty else {
            throw MoodBallCommandError.malformed
        }
        sessionID = returnedSession
        defaults.set(returnedSession, forKey: Keys.sessionID)
        let subscribed = try await request(
            action: "subscribe",
            fields: ["sessionId": returnedSession],
            timeout: 8
        )
        if let snapshot = decodeSnapshot(subscribed["snapshot"]) {
            sessionSnapshot = snapshot
        }
        return returnedSession
    }

    private func requireWorkspaceID() throws -> String {
        guard let id = selectedWorkspaceID,
              workspaces.contains(where: { $0.id == id }) else {
            throw MoodBallCommandError.server(code: "workspace/not-selected", message: "请先选择工作区")
        }
        return id
    }

    private func clearSessionBinding() {
        sessionID = nil
        sessionSnapshot = nil
        pendingRequestID = nil
        pendingRequestText = nil
        pendingRequestSignature = nil
        defaults.removeObject(forKey: Keys.sessionID)
        defaults.removeObject(forKey: Keys.requestID)
        defaults.removeObject(forKey: Keys.requestText)
        defaults.removeObject(forKey: Keys.requestSignature)
        continuationWarning = nil
    }

    private func connect() {
        guard started, connectionHandle == nil else { return }
        connection = .connecting
        receiveBuffer.removeAll(keepingCapacity: true)
        let handle = NWConnection(to: .unix(path: socketPath), using: .tcp)
        connectionHandle = handle
        handle.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    connection = .connected
                    flushQueuedPayloads()
                    refreshCapabilitiesAndWorkspaces()
                case .waiting:
                    // A Unix socket that is not available yet enters
                    // NWConnection.waiting rather than failed. Clear the
                    // handle so the retry loop can reconnect after Harness
                    // starts and creates the command socket.
                    connectionHandle = nil
                    connection = .disconnected
                    capabilitiesAvailable = false
                    taskListAvailable = false
                    imageAttachmentsAvailable = false
                    failPending(with: MoodBallCommandError.unavailable)
                    handle.cancel()
                    scheduleReconnect()
                case .failed, .cancelled:
                    connectionHandle = nil
                    connection = .disconnected
                    capabilitiesAvailable = false
                    taskListAvailable = false
                    imageAttachmentsAvailable = false
                    failPending(with: MoodBallCommandError.unavailable)
                    scheduleReconnect()
                default:
                    break
                }
            }
        }
        handle.start(queue: queue)
        receiveNext(on: handle)
    }

    private func receiveNext(on handle: NWConnection) {
        handle.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data { consume(data) }
                if isComplete {
                    connectionHandle = nil
                    connection = .disconnected
                    capabilitiesAvailable = false
                    taskListAvailable = false
                    imageAttachmentsAvailable = false
                    failPending(with: MoodBallCommandError.unavailable)
                    scheduleReconnect()
                } else if connectionHandle != nil {
                    receiveNext(on: handle)
                }
            }
        }
    }

    private func consume(_ data: Data) {
        receiveBuffer.append(data)
        while let newline = receiveBuffer.firstIndex(of: 10) {
            let line = receiveBuffer.prefix(upTo: newline)
            receiveBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if object["event"] as? String == "status" {
                if let sessionID = object["sessionId"] as? String,
                   sessionID == self.sessionID,
                   let snapshot = decodeSnapshot(object["snapshot"]) {
                    sessionSnapshot = snapshot
                }
                continue
            }
            if object["event"] as? String == "tasks" {
                applyTasks(object["tasks"])
                continue
            }
            guard let id = object["id"] as? String, let continuation = pending.removeValue(forKey: id) else { continue }
            if let ok = object["ok"] as? Bool, !ok {
                let error = object["error"] as? [String: Any]
                continuation(.failure(MoodBallCommandError.server(
                    code: error?["code"] as? String ?? "command-failed",
                    message: error?["message"] as? String ?? "MoodBall 插件拒绝了请求"
                )))
            } else {
                continuation(.success(object))
            }
        }
    }

    private func request(
        action: String,
        fields: [String: Any] = [:],
        timeout: TimeInterval = 8
    ) async throws -> [String: Any] {
        guard started else { throw MoodBallCommandError.unavailable }
        connect()
        let id = UUID().uuidString.lowercased()
        var object: [String: Any] = ["id": id, "action": action]
        for (key, value) in fields { object[key] = value }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = { result in continuation.resume(with: result) }
            queuedPayloads.append(data)
            if connection == .connected { flushQueuedPayloads() }
            Task { @MainActor [weak self] in
                let delay = UInt64(max(0.5, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                self?.timeOut(id)
            }
        }
    }

    private func refreshCapabilitiesAndWorkspaces() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await request(action: "capabilities", timeout: 5)
                guard response["protocolVersion"] as? Int == 1,
                      response["commandSocket"] as? Bool == true else {
                    throw MoodBallCommandError.malformed
                }
                capabilitiesAvailable = true
                let supports = response["supports"] as? [String] ?? []
                taskListAvailable = supports.contains("tasks") && supports.contains("subscribeTasks")
                imageAttachmentsAvailable = supports.contains("imageAttachments")
                imageLimits = decodeImageLimits(response["attachmentLimits"])
                if taskListAvailable { subscribeTasks() } else { tasks = [] }
                if let sessionID { subscribe(to: sessionID) }
                refreshWorkspaces()
            } catch {
                capabilitiesAvailable = false
                taskListAvailable = false
                imageAttachmentsAvailable = false
                imageLimits = nil
                record(error)
            }
        }
    }

    private func flushQueuedPayloads() {
        guard let connectionHandle, connection == .connected else { return }
        let payloads = queuedPayloads
        queuedPayloads.removeAll(keepingCapacity: true)
        for payload in payloads {
            connectionHandle.send(content: payload + Data([10]), completion: .contentProcessed { _ in })
        }
    }

    private func timeOut(_ id: String) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation(.failure(MoodBallCommandError.timedOut))
    }

    private func scheduleReconnect() {
        guard started, reconnectTask == nil else { return }
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.started else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }

    private func failPending(with error: Error) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation(.failure(error)) }
    }

    private func record(_ error: Error) {
        lastError = errorMessage(error)
        if case MoodBallCommandError.unavailable = error { connection = .disconnected }
    }

    private func decodeWorkspaces(_ value: Any?) -> [MoodBallWorkspace] {
        guard let value,
              let data = try? JSONSerialization.data(withJSONObject: value),
              let decoded = try? JSONDecoder().decode([MoodBallWorkspace].self, from: data) else { return [] }
        return decoded
    }

    private func decodeSnapshot(_ value: Any?) -> MoodBridgeSnapshot? {
        guard let value,
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(MoodBridgeSnapshot.self, from: data)
    }

    private func decodeImageLimits(_ value: Any?) -> MoodBallImageLimits? {
        guard let value,
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(MoodBallImageLimits.self, from: data)
    }

    private func addDraftImage(data: Data, mediaType: String, name: String) {
        do {
            let directory = try draftImageDirectory()
            let url = directory.appendingPathComponent("draft-\(UUID().uuidString.lowercased()).png")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            addDraftImageFile(url: url, data: data, mediaType: mediaType, name: name)
        } catch {
            lastError = errorMessage(error)
        }
    }

    private func addDraftImageFile(url: URL, data: Data, mediaType: String, name: String) {
        if let limits = imageLimits {
            guard draftImages.count < limits.maxImagesPerMessage else {
                try? FileManager.default.removeItem(at: url)
                lastError = "图片数量超过 Harness 限制（最多 \(limits.maxImagesPerMessage) 张）"
                return
            }
            guard data.count <= limits.maxImageBytes else {
                try? FileManager.default.removeItem(at: url)
                lastError = "图片超过 Harness 单张大小限制（\(Self.byteLabel(limits.maxImageBytes))）"
                return
            }
            guard draftImages.reduce(0, { $0 + $1.bytes }) + data.count <= limits.maxMessageImageBytes else {
                try? FileManager.default.removeItem(at: url)
                lastError = "图片总大小超过 Harness 限制（\(Self.byteLabel(limits.maxMessageImageBytes))）"
                return
            }
        }
        draftImages.append(MoodBallDraftImage(
            id: UUID().uuidString.lowercased(),
            path: url.path,
            mediaType: mediaType,
            name: name,
            bytes: data.count,
            error: nil
        ))
        invalidatePendingSubmission()
        persistDraftImages()
        lastError = nil
    }

    private func encodedDraftImages(_ images: [MoodBallDraftImage]) throws -> [[String: Any]] {
        try images.map { image in
            let data = try Data(contentsOf: image.fileURL, options: [.mappedIfSafe])
            return [
                "id": image.id,
                "mediaType": image.mediaType,
                "name": image.name,
                "data": data.base64EncodedString(),
            ]
        }
    }

    private func draftImageDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MoodBall/PrivateDraftImages", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        return root
    }

    private func clearDraftImages(ids: Set<String>) {
        for image in draftImages where ids.contains(image.id) {
            try? FileManager.default.removeItem(at: image.fileURL)
        }
        draftImages.removeAll { ids.contains($0.id) }
        persistDraftImages()
    }

    private func persistDraftImages() {
        if let data = try? JSONEncoder().encode(draftImages) {
            defaults.set(data, forKey: Keys.draftImages)
        }
    }

    private func invalidatePendingSubmission() {
        pendingRequestID = nil
        pendingRequestText = nil
        pendingRequestSignature = nil
        defaults.removeObject(forKey: Keys.requestID)
        defaults.removeObject(forKey: Keys.requestText)
        defaults.removeObject(forKey: Keys.requestSignature)
    }

    private func submissionSignature(text: String) -> String {
        ([text] + draftImages.map { "\($0.id):\($0.bytes)" }).joined(separator: "|")
    }

    private static func byteLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func subscribeTasks() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await request(action: "subscribeTasks", timeout: 12)
                applyTasks(response["tasks"])
            } catch {
                record(error)
            }
        }
    }

    private func subscribe(to sessionID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await request(
                    action: "subscribe",
                    fields: ["sessionId": sessionID],
                    timeout: 8
                )
                guard self.sessionID == sessionID else { return }
                if let snapshot = decodeSnapshot(response["snapshot"]) {
                    self.sessionSnapshot = snapshot
                }
            } catch {
                record(error)
            }
        }
    }

    private func applyTasks(_ value: Any?) {
        guard let value,
              let data = try? JSONSerialization.data(withJSONObject: value),
              let decoded = try? JSONDecoder().decode([MoodBallTaskSummary].self, from: data) else { return }

        if !hasReceivedTaskBaseline {
            // The first baseline is historical context, not a burst of unread
            // reminders. Retain existing markers so a result that arrived while
            // the App was closed can still be recognized after reconnect.
            for task in decoded where readMarkers[task.id] == nil {
                readMarkers[task.id] = TaskReadMarker(updatedAt: task.updatedAt, mood: task.mood)
            }
            hasReceivedTaskBaseline = true
            persistReadMarkers()
        }
        applyTaskSummaries(decoded)
    }

    /// Task-card history and the pet's live animation are separate state
    /// channels. In particular, a retained done/failed card must never replace
    /// the live Session snapshot merely because the card list refreshed.
    func applyTaskSummaries(_ decoded: [MoodBallTaskSummary]) {
        tasks = decoded
    }

    func isTaskUnread(_ task: MoodBallTaskSummary) -> Bool {
        guard hasReceivedTaskBaseline else { return false }
        guard let marker = readMarkers[task.id] else { return true }
        return marker.updatedAt != task.updatedAt || marker.mood != task.mood
    }

    private func markTaskRead(_ task: MoodBallTaskSummary) {
        readMarkers[task.id] = TaskReadMarker(updatedAt: task.updatedAt, mood: task.mood)
        persistReadMarkers()
    }

    private func persistReadMarkers() {
        guard let data = try? JSONEncoder().encode(readMarkers) else { return }
        defaults.set(data, forKey: Keys.taskReadMarkers)
    }

    private func taskRank(_ task: MoodBallTaskSummary) -> Int {
        if task.waitingForUser { return 0 }
        if isTaskUnread(task) && task.failed { return 1 }
        if isTaskUnread(task) && task.completed { return 2 }
        if task.taskRunning || task.running { return 3 }
        return 4
    }
}

private func errorMessage(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let message = localized.errorDescription { return message }
    return error.localizedDescription
}
