import Foundation
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
    @Published private(set) var workspaces: [MoodBallWorkspace] = []
    @Published private(set) var selectedWorkspaceID: String?
    @Published private(set) var sessionID: String?
    @Published private(set) var sessionSnapshot: MoodBridgeSnapshot?
    @Published private(set) var submissionStatus: MoodBallSubmissionStatus = .idle
    @Published private(set) var lastError: String?
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
    private var reconnectTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, socketPath: String = MoodBallCommandClient.defaultSocketPath) {
        self.defaults = defaults
        self.socketPath = socketPath
        selectedWorkspaceID = defaults.string(forKey: Keys.workspaceID)
        sessionID = defaults.string(forKey: Keys.sessionID)
        draft = defaults.string(forKey: Keys.draft) ?? ""
        pendingRequestID = defaults.string(forKey: Keys.requestID)
        pendingRequestText = defaults.string(forKey: Keys.requestText)
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

    var canSend: Bool {
        guard connection == .connected,
              capabilitiesAvailable,
              hasWorkspace,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              submissionStatus != .submitting else { return false }
        return !(sessionSnapshot?.taskRunning ?? false)
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
        guard workspaces.contains(where: { $0.id == id }) else { return }
        if selectedWorkspaceID != id {
            selectedWorkspaceID = id
            defaults.set(id, forKey: Keys.workspaceID)
            clearSessionBinding()
        }
    }

    /// Forget only MoodBall's current binding. Existing Harness sessions are
    /// never deleted or cancelled.
    func startNewSession() {
        clearSessionBinding()
        submissionStatus = .idle
        lastError = nil
    }

    func submitDraft() {
        guard submissionStatus != .submitting else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard selectedWorkspace != nil else {
            submissionStatus = .failed("请先选择工作区")
            return
        }
        if let busyMessage {
            submissionStatus = .failed(busyMessage)
            return
        }

        let requestID: String
        if pendingRequestText == text, let pendingRequestID {
            requestID = pendingRequestID
        } else {
            requestID = "moodball-\(UUID().uuidString.lowercased())"
            pendingRequestID = requestID
            pendingRequestText = text
            defaults.set(requestID, forKey: Keys.requestID)
            defaults.set(text, forKey: Keys.requestText)
        }

        submissionStatus = .submitting
        lastError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let sessionID = try await ensureSession()
                let workspaceID = try requireWorkspaceID()
                let response = try await request(
                    action: "prompt",
                    fields: [
                        "workspaceId": workspaceID,
                        "sessionId": sessionID,
                        "requestId": requestID,
                        "text": text,
                    ],
                    timeout: 32
                )
                guard response["ok"] as? Bool != false,
                      response["accepted"] as? Bool == true else {
                    throw MoodBallCommandError.malformed
                }
                draft = ""
                pendingRequestID = nil
                pendingRequestText = nil
                defaults.removeObject(forKey: Keys.requestID)
                defaults.removeObject(forKey: Keys.requestText)
                submissionStatus = .submitted
                onAccepted?()
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if submissionStatus == .submitted { submissionStatus = .idle }
            } catch {
                if case MoodBallCommandError.timedOut = error {
                    submissionStatus = .unconfirmed
                } else {
                    submissionStatus = .failed(errorMessage(error))
                }
                lastError = errorMessage(error)
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
        defaults.removeObject(forKey: Keys.sessionID)
        defaults.removeObject(forKey: Keys.requestID)
        defaults.removeObject(forKey: Keys.requestText)
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
                    failPending(with: MoodBallCommandError.unavailable)
                    handle.cancel()
                    scheduleReconnect()
                case .failed, .cancelled:
                    connectionHandle = nil
                    connection = .disconnected
                    capabilitiesAvailable = false
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
                refreshWorkspaces()
            } catch {
                capabilitiesAvailable = false
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
}

private func errorMessage(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let message = localized.errorDescription { return message }
    return error.localizedDescription
}
