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
    private var stateFilePollTask: Task<Void, Never>?
    private let costReader = CostReader()
    private let branchReader = GitBranchReader()

    private static let stateFilePath = "/tmp/screen-blocker/state.json"

    var workingInstances: [ClaudeInstance] {
        instances.values
            .filter { $0.status == .working }
            .sorted { $0.projectName.localizedCompare($1.projectName) == .orderedAscending }
    }

    var waitingInstances: [ClaudeInstance] {
        instances.values
            .filter { $0.status == .waitingInput }
            .sorted { $0.projectName.localizedCompare($1.projectName) == .orderedAscending }
    }

    var idleInstances: [ClaudeInstance] {
        instances.values
            .filter { $0.status == .idle }
            .sorted { $0.projectName.localizedCompare($1.projectName) == .orderedAscending }
    }

    var sortedInstances: [ClaudeInstance] {
        workingInstances + waitingInstances + idleInstances
    }

    // MARK: - Grouped by Project

    var workingGroups: [ProjectGroup] {
        groupByProject(workingInstances)
    }

    var waitingGroups: [ProjectGroup] {
        groupByProject(waitingInstances)
    }

    var idleGroups: [ProjectGroup] {
        groupByProject(idleInstances)
    }

    private func groupByProject(_ instances: [ClaudeInstance]) -> [ProjectGroup] {
        let grouped = Dictionary(grouping: instances) { $0.remoteURL ?? $0.projectName }
        return grouped
            .map { key, groupInstances in
                let displayName: String
                if let remoteURL = groupInstances.first?.remoteURL,
                   let repoName = GitBranchReader.repoName(from: remoteURL) {
                    displayName = repoName
                } else {
                    displayName = groupInstances.first?.projectName ?? key
                }
                return ProjectGroup(
                    groupKey: key,
                    displayName: displayName,
                    instances: groupInstances.sorted {
                        ($0.branchName ?? "").localizedCompare($1.branchName ?? "") == .orderedAscending
                    }
                )
            }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
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
            syncFromStateFile()
        }
        startStalePIDSweep()
        startStateFilePolling()
    }

    func cleanup() {
        staleSweepTask?.cancel()
        costPollTask?.cancel()
        stateFilePollTask?.cancel()
    }

    // MARK: - State File Sync

    private struct StateFile: Decodable {
        struct Instance: Decodable {
            let status: String
            let pid: Int
            let cwd: String
        }
        let instances: [String: Instance]
    }

    private func syncFromStateFile() {
        guard let data = FileManager.default.contents(atPath: Self.stateFilePath) else { return }
        guard let stateFile = try? JSONDecoder().decode(StateFile.self, from: data) else { return }

        // Track which sessions are in the file
        var fileSessionIds = Set<String>()

        for (sessionId, inst) in stateFile.instances {
            guard isProcessAlive(pid: inst.pid) else { continue }
            fileSessionIds.insert(sessionId)

            let status: InstanceStatus = inst.status == "active" ? .working : .idle

            if let existing = instances[sessionId] {
                if existing.status != status {
                    existing.status = status
                }
                if existing.pid != inst.pid {
                    existing.pid = inst.pid
                }
                if existing.cwd != inst.cwd {
                    existing.cwd = inst.cwd
                    existing.projectName = (inst.cwd as NSString).lastPathComponent
                    existing.branchName = branchReader.readBranch(forDirectory: inst.cwd)
                }
            } else {
                // New instance
                let instance = ClaudeInstance(id: sessionId, pid: inst.pid, cwd: inst.cwd, status: status)
                instance.branchName = branchReader.readBranch(forDirectory: inst.cwd)
                instance.remoteURL = branchReader.readRemoteURL(forDirectory: inst.cwd)
                instances[sessionId] = instance
            }
        }

        // Remove instances that are no longer in the state file
        let removedIds = Set(instances.keys).subtracting(fileSessionIds)
        for id in removedIds {
            instances.removeValue(forKey: id)
        }
    }

    private func startStateFilePolling() {
        stateFilePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.syncFromStateFile()
            }
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
            if existing.cwd != event.cwd {
                existing.cwd = event.cwd
                existing.projectName = (event.cwd as NSString).lastPathComponent
                existing.branchName = branchReader.readBranch(forDirectory: event.cwd)
                existing.remoteURL = branchReader.readRemoteURL(forDirectory: event.cwd)
            }
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
            instance.branchName = branchReader.readBranch(forDirectory: event.cwd)
            instance.remoteURL = branchReader.readRemoteURL(forDirectory: event.cwd)
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
        guard kill(Int32(pid), 0) == 0 else { return false }

        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let pathLength = proc_pidpath(Int32(pid), &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else { return true }

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
            instance.branchName = branchReader.readBranch(forDirectory: instance.cwd)
            if instance.remoteURL == nil {
                instance.remoteURL = branchReader.readRemoteURL(forDirectory: instance.cwd)
            }
        }
    }
}
