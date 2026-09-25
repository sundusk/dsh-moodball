import Foundation
import Combine

/// Coordinates the local-first transport policy and exposes one stable stream
/// to the pet model. The local socket keeps retrying while HTTP is the fallback.
@MainActor
final class MoodBridge: ObservableObject {
    @Published private(set) var snapshot = MoodBridgeSnapshot.disconnected
    @Published private(set) var connection: TransportConnection = .unavailable
    @Published private(set) var transportKind: TransportKind = .disconnected

    private let local: LocalSocketTransport
    private let http: HTTPPollingTransport
    private var fallbackTask: Task<Void, Never>?
    private var isRunning = false

    init(settings: SettingsStore? = nil) {
        let settings = settings ?? SettingsStore.shared
        local = LocalSocketTransport()
        http = HTTPPollingTransport(
            baseURL: settings.apiBase,
            pollInterval: settings.pollInterval,
            requestTimeout: settings.requestTimeout
        )
        wire(local, kind: .localSocket)
        wire(http, kind: .http)
    }

    func start() {
        guard fallbackTask == nil, !local.isConnected, !http.isConnected else { return }
        isRunning = true
        connection = .unavailable
        transportKind = .disconnected
        local.connect()
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.startHTTPFallback()
        }
    }

    func stop() {
        isRunning = false
        fallbackTask?.cancel()
        fallbackTask = nil
        local.disconnect()
        http.disconnect()
        connection = .unavailable
        transportKind = .disconnected
        snapshot = .disconnected
    }

    func updateHTTPConfiguration(settings: SettingsStore) {
        http.updateConfiguration(
            baseURL: settings.apiBase,
            pollInterval: settings.pollInterval,
            requestTimeout: settings.requestTimeout
        )
    }

    private func wire(_ transport: any HarnessStateTransport, kind: TransportKind) {
        transport.onStateChanged = { [weak self] snapshot in
            guard let self else { return }
            if kind == .http && self.local.isConnected { return }
            self.snapshot = snapshot
            self.transportKind = kind
        }
        transport.onConnectionChanged = { [weak self] status in
            guard let self else { return }
            if kind == .http && self.local.isConnected { return }
            self.connection = status
            if status == .connected {
                self.transportKind = kind
                if kind == .localSocket {
                    self.http.disconnect()
                    self.fallbackTask?.cancel()
                    self.fallbackTask = nil
                }
            } else if kind == .localSocket && status == .unavailable && self.isRunning && self.fallbackTask == nil {
                self.startHTTPFallback()
            }
        }
    }

    private func startHTTPFallback() {
        fallbackTask = nil
        guard !local.isConnected else { return }
        transportKind = .http
        http.connect()
    }
}
