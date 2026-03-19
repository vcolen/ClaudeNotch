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

    /// Grace period for keeping socket-created instances that may not yet appear in the state file.
    /// Must exceed the state file polling interval (2s) to avoid flicker during sync gaps.
    private static let staleGracePeriod: TimeInterval = 5

    #if DEBUG
    /// Override for testing; when set, replaces the real process-liveness check.
    nonisolated(unsafe) static var testProcessAliveOverride: ((Int) -> Bool)?
    #endif

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

    // MARK: - PID Deduplication

    /// Returns the existing instance that shares the given PID, if any.
    /// Guards against PID 0 to prevent false deduplication when PID is unknown or unset.
    private func existingInstance(forPID pid: Int) -> ClaudeInstance? {
        guard pid > 0 else {
            assertionFailure("existingInstance(forPID:) called with pid <= 0")
            return nil
        }
        return instances.values.first { $0.pid == pid }
    }

    /// Shared metadata update logic for both socket events and state file sync.
    private func updateInstanceMetadata(_ instance: ClaudeInstance, pid: Int, cwd: String) {
        instance.pid = pid
        if instance.cwd != cwd {
            instance.cwd = cwd
            instance.projectName = (cwd as NSString).lastPathComponent
            instance.branchName = branchReader.readBranch(forDirectory: cwd)
            instance.remoteURL = branchReader.readRemoteURL(forDirectory: cwd)
        }
    }

    // MARK: - State File Sync

    struct StateFile: Decodable {
        struct Instance: Decodable {
            let status: String
            let pid: Int
            let cwd: String
        }
        let instances: [String: Instance]
    }

    func sync(from stateFile: StateFile) {
        var activeCanonicalIds = Set<String>()

        // Sort entries so already-known sessions are processed first,
        // ensuring subagents resolve to existing canonical instances
        let sortedEntries = stateFile.instances.sorted { a, b in
            let aExists = self.instances[a.key] != nil
            let bExists = self.instances[b.key] != nil
            if aExists != bExists { return aExists }
            return a.key < b.key
        }

        for (sessionId, inst) in sortedEntries {
            guard inst.pid > 0 else {
                NSLog("InstanceManager: state file entry '%@' has invalid PID %ld, skipping", sessionId, inst.pid)
                continue
            }
            guard isProcessAlive(pid: inst.pid) else { continue }

            // PID dedup: use existing PID-holder's ID, or default to this session's ID
            let resolvedId = existingInstance(forPID: inst.pid)?.id ?? sessionId
            let isDedupedEntry = (resolvedId != sessionId)
            activeCanonicalIds.insert(resolvedId)

            let status = mapStatus(inst.status)

            if let existing = instances[resolvedId] {
                // Skip status transitions for deduped (subagent) entries —
                // subagent status changes should not trigger attention alerts on the canonical instance
                if !isDedupedEntry && !existing.statusFromSocket && existing.status != status {
                    applyStatusTransition(on: existing, newStatus: status)
                }
                existing.updatedAt = Date()
                updateInstanceMetadata(existing, pid: inst.pid, cwd: inst.cwd)
            } else {
                let instance = ClaudeInstance(id: resolvedId, pid: inst.pid, cwd: inst.cwd, status: status)
                instance.branchName = branchReader.readBranch(forDirectory: inst.cwd)
                instance.remoteURL = branchReader.readRemoteURL(forDirectory: inst.cwd)
                instances[resolvedId] = instance
            }
        }

        // Remove instances no longer in state file,
        // but keep recently-updated instances (socket events may be ahead of state file)
        let staleThreshold = Date().addingTimeInterval(-Self.staleGracePeriod)
        let removedIds = Set(instances.keys).subtracting(activeCanonicalIds)
        for id in removedIds {
            if let instance = instances[id], instance.updatedAt > staleThreshold {
                continue
            }
            instances.removeValue(forKey: id)
        }
    }

    private func syncFromStateFile() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: Self.stateFilePath) else { return }
        guard let data = fileManager.contents(atPath: Self.stateFilePath) else {
            NSLog("InstanceManager: state file exists but could not be read at %@", Self.stateFilePath)
            return
        }
        let stateFile: StateFile
        do {
            stateFile = try JSONDecoder().decode(StateFile.self, from: data)
        } catch {
            NSLog("InstanceManager: failed to decode state file: %@", "\(error)")
            return
        }
        sync(from: stateFile)
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
        if event.status == "ended" {
            // Remove by direct key match only. If the session_id isn't a key,
            // it's a subagent ending — the canonical instance should stay alive.
            // The stale PID sweep handles cleanup when the process truly dies.
            instances.removeValue(forKey: event.sessionId)
            return
        }

        guard event.pid > 0 else {
            NSLog("InstanceManager: dropping socket event with invalid PID %ld for session %@", event.pid, event.sessionId)
            return
        }
        let mappedStatus = mapStatus(event.status)

        // Resolve target: direct session_id match, or PID-based dedup
        let target = instances[event.sessionId] ?? existingInstance(forPID: event.pid)
        let isDirectMatch = instances[event.sessionId] != nil

        if let existing = target {
            // Only apply status transitions from the session's own events (isDirectMatch),
            // not from subagent events resolved via PID (which would cause false attention alerts)
            if isDirectMatch && existing.status != mappedStatus {
                applyStatusTransition(on: existing, newStatus: mappedStatus)
            }
            existing.updatedAt = Date()
            updateInstanceMetadata(existing, pid: event.pid, cwd: event.cwd)
            if isDirectMatch {
                existing.statusFromSocket = true
                if let tty = event.tty { existing.tty = tty }
            }
            if let tool = event.tool { existing.lastTool = tool }
        } else {
            let instance = ClaudeInstance(
                id: event.sessionId, pid: event.pid, cwd: event.cwd,
                status: mappedStatus, tty: event.tty
            )
            instance.statusFromSocket = true
            instance.branchName = branchReader.readBranch(forDirectory: event.cwd)
            instance.remoteURL = branchReader.readRemoteURL(forDirectory: event.cwd)
            if let tool = event.tool { instance.lastTool = tool }
            instances[event.sessionId] = instance
        }
    }

    private func mapStatus(_ status: String) -> InstanceStatus {
        switch status {
        case "active", "processing", "running_tool", "compacting":
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
        #if DEBUG
        if let override = Self.testProcessAliveOverride {
            return override(pid)
        }
        #endif
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
