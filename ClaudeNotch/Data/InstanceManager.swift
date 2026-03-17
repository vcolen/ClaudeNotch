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
            .filter { $0.status == .working && !$0.needsAttention }
            .sorted { $0.projectName.localizedCompare($1.projectName) == .orderedAscending }
    }

    var waitingInstances: [ClaudeInstance] {
        instances.values
            .filter { $0.status == .waitingInput && !$0.needsAttention }
            .sorted { $0.projectName.localizedCompare($1.projectName) == .orderedAscending }
    }

    var idleInstances: [ClaudeInstance] {
        instances.values
            .filter { $0.status == .idle && !$0.needsAttention }
            .sorted { $0.projectName.localizedCompare($1.projectName) == .orderedAscending }
    }

    var needsAttentionInstances: [ClaudeInstance] {
        instances.values
            .filter { $0.needsAttention }
            .sorted { $0.projectName.localizedCompare($1.projectName) == .orderedAscending }
    }

    var sortedInstances: [ClaudeInstance] {
        needsAttentionInstances + workingInstances + waitingInstances + idleInstances
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

    var needsAttentionGroups: [ProjectGroup] {
        groupByProject(needsAttentionInstances)
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

    var activeCount: Int { workingInstances.count }
    var waitingCount: Int { waitingInstances.count }
    var idleCount: Int { idleInstances.count }
    var needsAttentionCount: Int { needsAttentionInstances.count }

    // MARK: - Attention Management

    func clearAttention(for sessionId: String) {
        instances[sessionId]?.needsAttention = false
    }

    private func applyStatusTransition(on instance: ClaudeInstance, newStatus: InstanceStatus) {
        let previousStatus = instance.status
        instance.status = newStatus
        // needsAttention is set when leaving .working and cleared when entering .working.
        // It intentionally persists across non-working transitions (e.g. waitingInput → idle)
        // so the notification stays visible until the user explicitly clears it.
        if previousStatus == .working && newStatus != .working {
            instance.needsAttention = true
        } else if newStatus == .working {
            instance.needsAttention = false
        }
    }

    init(skipBootstrap: Bool = false) {
        if !skipBootstrap {
            syncFromStateFile()
            startStalePIDSweep()
            startStateFilePolling()
        }
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
        let stateFile: StateFile
        do {
            stateFile = try JSONDecoder().decode(StateFile.self, from: data)
        } catch {
            NSLog("InstanceManager: failed to decode state file: %@", "\(error)")
            return
        }

        // Track which sessions are in the file
        var fileSessionIds = Set<String>()

        for (sessionId, inst) in stateFile.instances {
            guard isProcessAlive(pid: inst.pid) else { continue }
            fileSessionIds.insert(sessionId)

            // Validate cwd like handleSocketEvent does
            let cwd: String
            if inst.cwd.count <= 512, inst.cwd.hasPrefix("/") {
                cwd = inst.cwd
            } else {
                cwd = "/tmp"
            }

            let status: InstanceStatus = inst.status == "active" ? .working : .idle

            if let existing = instances[sessionId] {
                if existing.status != status {
                    applyStatusTransition(on: existing, newStatus: status)
                }
                if existing.pid != inst.pid {
                    existing.pid = inst.pid
                }
                if existing.cwd != cwd {
                    existing.cwd = cwd
                    existing.projectName = String((cwd as NSString).lastPathComponent.prefix(100))
                    existing.branchName = branchReader.readBranch(forDirectory: cwd).map { String($0.prefix(100)) }
                }
            } else {
                // New instance
                let instance = ClaudeInstance(id: sessionId, pid: inst.pid, cwd: cwd, status: status)
                instance.projectName = String(instance.projectName.prefix(100))
                instance.branchName = branchReader.readBranch(forDirectory: cwd).map { String($0.prefix(100)) }
                instance.remoteURL = branchReader.readRemoteURL(forDirectory: cwd)
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
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
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

        // Validate tty at entry
        let sanitizedTTY: String?
        if let tty = event.tty {
            sanitizedTTY = ITermIntegration.sanitizeTTY(tty)
        } else {
            sanitizedTTY = nil
        }

        // Cap cwd length and validate basic path format
        let cwd: String
        if event.cwd.count <= 512, event.cwd.hasPrefix("/") {
            cwd = event.cwd
        } else {
            cwd = "/tmp"
        }

        if let existing = instances[event.sessionId] {
            applyStatusTransition(on: existing, newStatus: mappedStatus)
            existing.updatedAt = Date()
            existing.pid = event.pid

            if existing.cwd != cwd {
                existing.cwd = cwd
                existing.projectName = String((cwd as NSString).lastPathComponent.prefix(100))
                existing.branchName = branchReader.readBranch(forDirectory: cwd).map { String($0.prefix(100)) }
                existing.remoteURL = branchReader.readRemoteURL(forDirectory: cwd)
            }
            if let tty = sanitizedTTY {
                existing.tty = tty
            }
            if let tool = event.tool {
                existing.lastTool = tool
            }
        } else {
            let instance = ClaudeInstance(
                id: event.sessionId,
                pid: event.pid,
                cwd: cwd,
                status: mappedStatus,
                tty: sanitizedTTY
            )
            instance.projectName = String(instance.projectName.prefix(100))
            instance.branchName = branchReader.readBranch(forDirectory: cwd).map { String($0.prefix(100)) }
            instance.remoteURL = branchReader.readRemoteURL(forDirectory: cwd)
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
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
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
        costPollTask = Task { [weak self] in
            await self?.refreshCosts()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    break
                }
                await self?.refreshCosts()
            }
        }
    }

    func stopCostPolling() {
        costPollTask?.cancel()
        costPollTask = nil
    }

    private func refreshCosts() async {
        let instanceData = instances.values.map { (id: $0.id, pid: $0.pid, cwd: $0.cwd, remoteURL: $0.remoteURL) }

        let results = await Task.detached { [costReader, branchReader] in
            instanceData.map { inst in
                let cost = costReader.readCost(forPID: inst.pid)
                let branch = branchReader.readBranch(forDirectory: inst.cwd)
                let remote = inst.remoteURL ?? branchReader.readRemoteURL(forDirectory: inst.cwd)
                return (id: inst.id, cost: cost, branch: branch, remote: remote)
            }
        }.value

        for result in results {
            guard let instance = instances[result.id] else { continue }
            if let costInfo = result.cost {
                instance.cost = costInfo.totalCost
                instance.model = costInfo.model
                instance.contextUsagePercent = costInfo.contextPercent
            }
            instance.branchName = result.branch
            if instance.remoteURL == nil {
                instance.remoteURL = result.remote
            }
        }
    }
}
