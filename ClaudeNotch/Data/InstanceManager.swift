import Foundation
import Observation
import Darwin

@MainActor
@Observable
final class InstanceManager {
    var instances: [String: ClaudeInstance] = [:]
    var isExpanded = false

    private var staleSweepTask: Task<Void, Never>?
    private var costPollTask: Task<Void, Never>?
    private let costReader = CostReader()

    var sortedInstances: [ClaudeInstance] {
        instances.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeCount: Int {
        instances.values.filter { $0.status == .working }.count
    }

    var waitingCount: Int {
        instances.values.filter { $0.status == .waitingInput }.count
    }

    var idleCount: Int {
        instances.values.filter { $0.status == .idle }.count
    }

    init(skipBootstrap: Bool = false) {
        if !skipBootstrap {
            bootstrapFromStateFile()
        }
        startStalePIDSweep()
    }

    func cleanup() {
        staleSweepTask?.cancel()
        costPollTask?.cancel()
    }

    // MARK: - Bootstrap

    private func bootstrapFromStateFile() {
        let stateFilePath = "/tmp/screen-blocker/state.json"
        guard let data = FileManager.default.contents(atPath: stateFilePath) else { return }

        struct StateFile: Decodable {
            struct Instance: Decodable {
                let status: String
                let pid: Int
                let cwd: String
            }
            let instances: [String: Instance]
        }

        guard let stateFile = try? JSONDecoder().decode(StateFile.self, from: data) else { return }

        for (sessionId, inst) in stateFile.instances {
            guard isProcessAlive(pid: inst.pid) else { continue }
            let status: InstanceStatus = inst.status == "active" ? .working : .idle
            let instance = ClaudeInstance(id: sessionId, pid: inst.pid, cwd: inst.cwd, status: status)
            instances[sessionId] = instance
        }
    }

    // MARK: - Socket Event Handling

    struct SocketEvent: Sendable {
        let sessionId: String
        let pid: Int
        let cwd: String
        let status: String
        let tty: String?
        let tool: String?
    }

    func handleSocketEvent(_ event: SocketEvent) {
        let mappedStatus = mapStatus(event.status)

        if event.status == "ended" {
            instances.removeValue(forKey: event.sessionId)
            return
        }

        if let existing = instances[event.sessionId] {
            existing.status = mappedStatus
            existing.updatedAt = Date()
            existing.pid = event.pid
            existing.cwd = event.cwd
            existing.projectName = (event.cwd as NSString).lastPathComponent
            if let tty = event.tty {
                existing.tty = tty
            }
            if let tool = event.tool {
                existing.lastTool = tool
            }
        } else {
            let instance = ClaudeInstance(
                id: event.sessionId,
                pid: event.pid,
                cwd: event.cwd,
                status: mappedStatus,
                tty: event.tty
            )
            if let tool = event.tool {
                instance.lastTool = tool
            }
            instances[event.sessionId] = instance
        }
    }

    private func mapStatus(_ status: String) -> InstanceStatus {
        switch status {
        case "processing", "running_tool", "compacting":
            return .working
        case "waiting_for_input", "waiting_for_approval":
            return .waitingInput
        default:
            return .idle
        }
    }

    // MARK: - Stale PID Sweep

    private func startStalePIDSweep() {
        staleSweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await self?.sweepStaleInstances()
            }
        }
    }

    private func sweepStaleInstances() {
        let staleIds = instances.filter { !isProcessAlive(pid: $0.value.pid) }.map(\.key)
        for id in staleIds {
            instances.removeValue(forKey: id)
        }
    }

    private nonisolated func isProcessAlive(pid: Int) -> Bool {
        // Check if process exists
        guard kill(Int32(pid), 0) == 0 else { return false }

        // Verify it's a claude process using proc_pidpath
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let pathLength = proc_pidpath(Int32(pid), &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else { return true } // If we can't check path, assume alive

        let path = String(cString: pathBuffer)
        return path.contains("claude") || path.contains("node")
    }

    // MARK: - Cost Polling

    func startCostPolling() {
        costPollTask?.cancel()
        refreshCosts()
        costPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await self?.refreshCosts()
            }
        }
    }

    func stopCostPolling() {
        costPollTask?.cancel()
        costPollTask = nil
    }

    private func refreshCosts() {
        for instance in instances.values {
            if let costInfo = costReader.readCost(forPID: instance.pid) {
                instance.cost = costInfo.totalCost
                instance.model = costInfo.model
                instance.contextUsagePercent = costInfo.contextPercent
            }
        }
    }
}
