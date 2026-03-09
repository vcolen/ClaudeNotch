import Foundation
import Network
import os.log

/// Listens on a Unix domain socket for JSON events from Claude hooks
/// and forwards them via a callback.
final class SocketListener: @unchecked Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.claudenotch",
        category: "SocketListener"
    )

    private let socketDir: String
    private let socketPath: String
    private let listener: NWListener

    /// Called on an arbitrary queue with each parsed event.
    var onEvent: (@Sendable (InstanceManager.SocketEvent) -> Void)?

    // Batch buffer
    private let buffer = LockedBuffer()
    private var flushTask: Task<Void, Never>?

    // MARK: - Initializer

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.socketDir = "\(home)/.claude/run"
        self.socketPath = "\(socketDir)/claude-notch.sock"

        // Ensure directory with 0700 permissions
        try? FileManager.default.createDirectory(
            atPath: socketDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Remove stale socket
        unlink(socketPath)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)

        self.listener = try! NWListener(using: params)
    }

    // MARK: - Start / Stop

    func start() {
        listener.stateUpdateHandler = { [socketPath] state in
            switch state {
            case .ready:
                Self.logger.info("Listening on \(socketPath)")
            case .failed(let error):
                Self.logger.error("Listener failed: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: .global(qos: .userInitiated))
        startFlushLoop()
    }

    func stop() {
        flushTask?.cancel()
        listener.cancel()
        unlink(socketPath)
        Self.logger.info("Socket listener stopped, socket removed")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        Task {
            do {
                let data = try await readAll(from: connection)
                connection.cancel()

                guard let event = parseEvent(data) else { return }
                buffer.append(event)
            } catch {
                connection.cancel()
                Self.logger.error("Connection read error: \(error)")
            }
        }
    }

    private func readAll(from connection: NWConnection) async throws -> Data {
        var accumulated = Data()

        while true {
            let chunk: Data? = try await withCheckedThrowingContinuation { continuation in
                connection.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: 65536
                ) { content, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let content, !content.isEmpty {
                        continuation.resume(returning: content)
                    } else if isComplete {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }

            guard let chunk else { break }
            accumulated.append(chunk)
        }

        return accumulated
    }

    // MARK: - JSON Parsing

    private struct RawEvent: Decodable {
        let session_id: String
        let pid: Int
        let cwd: String
        let status: String
        let tty: String?
        let tool: String?
    }

    private func parseEvent(_ data: Data) -> InstanceManager.SocketEvent? {
        guard let raw = try? JSONDecoder().decode(RawEvent.self, from: data) else {
            Self.logger.warning("Failed to decode socket event")
            return nil
        }
        return InstanceManager.SocketEvent(
            sessionId: raw.session_id,
            pid: raw.pid,
            cwd: raw.cwd,
            status: raw.status,
            tty: raw.tty,
            tool: raw.tool
        )
    }

    // MARK: - Batch Flush (200ms)

    private func startFlushLoop() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                let events = self.buffer.drain()
                guard !events.isEmpty else { continue }
                for event in events {
                    self.onEvent?(event)
                }
            }
        }
    }
}

// MARK: - Thread-safe batch buffer

private final class LockedBuffer: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var storage: [InstanceManager.SocketEvent] = []

    func append(_ event: InstanceManager.SocketEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    func drain() -> [InstanceManager.SocketEvent] {
        lock.lock()
        let events = storage
        storage.removeAll()
        lock.unlock()
        return events
    }
}
