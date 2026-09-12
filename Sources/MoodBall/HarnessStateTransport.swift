import Foundation
import Network

enum TransportConnection: Equatable {
    case connected
    case pluginDisabled
    case unavailable
}

enum TransportKind: String {
    case localSocket = "本地桥接"
    case http = "HTTP 兼容"
    case disconnected = "未连接"
}

@MainActor
protocol HarnessStateTransport: AnyObject {
    var kind: TransportKind { get }
    var isConnected: Bool { get }
    var onStateChanged: ((MoodBridgeSnapshot) -> Void)? { get set }
    var onConnectionChanged: ((TransportConnection) -> Void)? { get set }

    func connect()
    func disconnect()
}

/// Compatibility transport for existing `GET /api/moodball/status` installs.
@MainActor
final class HTTPPollingTransport: HarnessStateTransport {
    let kind: TransportKind = .http
    private(set) var isConnected = false

    var onStateChanged: ((MoodBridgeSnapshot) -> Void)?
    var onConnectionChanged: ((TransportConnection) -> Void)?

    private var baseURL: String
    private var pollInterval: TimeInterval
    private var requestTimeout: TimeInterval
    private var pollingTask: Task<Void, Never>?

    init(baseURL: String, pollInterval: TimeInterval, requestTimeout: TimeInterval) {
        self.baseURL = baseURL
        self.pollInterval = pollInterval
        self.requestTimeout = requestTimeout
    }

    func updateConfiguration(baseURL: String, pollInterval: TimeInterval, requestTimeout: TimeInterval) {
        self.baseURL = baseURL
        self.pollInterval = pollInterval
        self.requestTimeout = requestTimeout
    }

    func connect() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                guard !Task.isCancelled else { return }
                let delay = UInt64(max(0.3, self?.pollInterval ?? 0.7) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        isConnected = false
    }

    private func pollOnce() async {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/api/moodball/status") else {
            mark(.unavailable)
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 404 {
                mark(.pluginDisabled)
                return
            }
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let snapshot = try JSONDecoder().decode(MoodBridgeSnapshot.self, from: data)
            onStateChanged?(snapshot)
            mark(.connected)
        } catch {
            mark(.unavailable)
        }
    }

    private func mark(_ status: TransportConnection) {
        let connected = status == .connected
        if isConnected != connected { isConnected = connected }
        onConnectionChanged?(status)
    }
}

/// New local transport. It observes newline-delimited JSON from the plugin's
/// Unix domain socket and never owns the Harness process or socket server.
@MainActor
final class LocalSocketTransport: HarnessStateTransport {
    let kind: TransportKind = .localSocket
    private(set) var isConnected = false

    var onStateChanged: ((MoodBridgeSnapshot) -> Void)?
    var onConnectionChanged: ((TransportConnection) -> Void)?

    private let socketPath: String
    private let queue = DispatchQueue(label: "com.sundusk.moodball.local-transport")
    private var connection: NWConnection?
    private var buffer = Data()

    init(socketPath: String = LocalSocketTransport.defaultSocketPath) {
        self.socketPath = socketPath
    }

    nonisolated static var defaultSocketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/MoodBall/moodball.sock"
    }

    func connect() {
        guard connection == nil else { return }
        buffer.removeAll(keepingCapacity: true)
        let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.onConnectionChanged?(.connected)
                    self.receiveNext()
                case .failed, .cancelled:
                    self.isConnected = false
                    self.onConnectionChanged?(.unavailable)
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: false)
        isConnected = false
    }

    private func receiveNext() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data { self.consume(data) }
                if isComplete {
                    self.isConnected = false
                    self.onConnectionChanged?(.unavailable)
                } else if self.connection != nil {
                    self.receiveNext()
                }
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            if let snapshot = try? JSONDecoder().decode(MoodBridgeSnapshot.self, from: line) {
                onStateChanged?(snapshot)
            }
        }
    }
}
