import Foundation
import Testing
@testable import ClaudeNotch

@Suite("InstanceManager Tests")
struct InstanceManagerTests {

    // MARK: - Status Mapping

    @Test("Socket event 'processing' maps to .working")
    @MainActor func processingMapsToWorking() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .working)
    }

    @Test("Socket event 'running_tool' maps to .working")
    @MainActor func runningToolMapsToWorking() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "running_tool", tty: nil, tool: "Bash"
        ))
        #expect(manager.instances["s1"]?.status == .working)
        #expect(manager.instances["s1"]?.lastTool == "Bash")
    }

    @Test("Socket event 'compacting' maps to .working")
    @MainActor func compactingMapsToWorking() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "compacting", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .working)
    }

    @Test("Socket event 'waiting_for_input' maps to .waitingInput")
    @MainActor func waitingForInputMapsToWaiting() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .waitingInput)
    }

    @Test("Socket event 'waiting_for_approval' maps to .waitingInput")
    @MainActor func waitingForApprovalMapsToWaiting() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_approval", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .waitingInput)
    }

    @Test("Unknown status maps to .idle")
    @MainActor func unknownMapsToIdle() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "something_else", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .idle)
    }

    // MARK: - Instance Lifecycle

    @Test("New socket event creates instance")
    @MainActor func newEventCreatesInstance() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/Users/test/project",
            status: "processing", tty: "/dev/ttys001", tool: nil
        ))
        #expect(manager.instances.count == 1)
        #expect(manager.instances["s1"]?.projectName == "project")
        #expect(manager.instances["s1"]?.tty == "/dev/ttys001")
    }

    @Test("Socket event updates existing instance")
    @MainActor func eventUpdatesExisting() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: "/dev/ttys002", tool: nil
        ))
        #expect(manager.instances.count == 1)
        #expect(manager.instances["s1"]?.status == .waitingInput)
        #expect(manager.instances["s1"]?.tty == "/dev/ttys002")
    }

    @Test("'ended' status removes instance")
    @MainActor func endedRemovesInstance() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances.count == 1)

        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "ended", tty: nil, tool: nil
        ))
        #expect(manager.instances.isEmpty)
    }

    // MARK: - Computed Properties

    @Test("Sorted instances ordered by status priority")
    @MainActor func sortedInstancesOrder() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/b",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        let sorted = manager.sortedInstances
        #expect(sorted.count == 2)
        #expect(sorted.first?.id == "s1") // Working instances come first
    }

    // MARK: - Project Grouping

    @Test("Same project instances are grouped into one ProjectGroup")
    @MainActor func sameProjectGrouped() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/myproject",
            status: "unknown", tty: nil, tool: nil
        ))
        manager.instances["s1"]?.branchName = "main"
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/myproject",
            status: "unknown", tty: nil, tool: nil
        ))
        manager.instances["s2"]?.branchName = "feature/a"
        manager.handleSocketEvent(.init(
            sessionId: "s3", pid: 102, cwd: "/tmp/myproject",
            status: "unknown", tty: nil, tool: nil
        ))
        manager.instances["s3"]?.branchName = "feature/b"

        let groups = manager.idleGroups
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
        #expect(groups[0].displayName == "myproject")
    }

    @Test("Different projects produce separate groups sorted alphabetically")
    @MainActor func differentProjectsSortedAlphabetically() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/zebra",
            status: "unknown", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/alpha",
            status: "unknown", tty: nil, tool: nil
        ))

        let groups = manager.idleGroups
        #expect(groups.count == 2)
        #expect(groups[0].displayName == "alpha")
        #expect(groups[1].displayName == "zebra")
    }

    @Test("Single-instance project has isSingle true")
    @MainActor func singleInstanceGroupIsSingle() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/solo",
            status: "unknown", tty: nil, tool: nil
        ))

        let groups = manager.idleGroups
        #expect(groups.count == 1)
        #expect(groups[0].isSingle == true)
    }

    @Test("Instances within a group are sorted by branchName")
    @MainActor func instancesSortedByBranch() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/proj",
            status: "unknown", tty: nil, tool: nil
        ))
        manager.instances["s1"]?.branchName = "z-branch"
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/proj",
            status: "unknown", tty: nil, tool: nil
        ))
        manager.instances["s2"]?.branchName = "a-branch"

        let groups = manager.idleGroups
        #expect(groups.count == 1)
        #expect(groups[0].instances[0].branchName == "a-branch")
        #expect(groups[0].instances[1].branchName == "z-branch")
    }

    @Test("Instances with same remoteURL but different cwds are grouped together")
    @MainActor func remoteURLGrouping() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project-worktree1",
            status: "unknown", tty: nil, tool: nil
        ))
        manager.instances["s1"]?.remoteURL = "git@github.com:user/my-repo.git"
        manager.instances["s1"]?.branchName = "main"
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/project-worktree2",
            status: "unknown", tty: nil, tool: nil
        ))
        manager.instances["s2"]?.remoteURL = "git@github.com:user/my-repo.git"
        manager.instances["s2"]?.branchName = "feature"

        let groups = manager.idleGroups
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
        #expect(groups[0].displayName == "my-repo")
    }

    @Test("repoName extracts name from SSH and HTTPS URLs")
    func repoNameExtraction() {
        #expect(GitBranchReader.repoName(from: "git@github.com:user/my-repo.git") == "my-repo")
        #expect(GitBranchReader.repoName(from: "https://github.com/user/my-repo.git") == "my-repo")
        #expect(GitBranchReader.repoName(from: "https://github.com/user/my-repo") == "my-repo")
    }

    // MARK: - Attention State

    @Test("Working to waiting sets needsAttention and attentionType .needsInput")
    @MainActor func workingToWaitingSetsAttention() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == false)
        #expect(manager.instances["s1"]?.attentionType == nil)

        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == true)
        #expect(manager.instances["s1"]?.attentionType == .needsInput)
    }

    @Test("Working to idle sets needsAttention and attentionType .taskFinished")
    @MainActor func workingToIdleSetsAttention() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "unknown", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == true)
        #expect(manager.instances["s1"]?.attentionType == .taskFinished)
    }

    @Test("Resuming work clears needsAttention and attentionType")
    @MainActor func resumingWorkClearsAttention() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == true)
        #expect(manager.instances["s1"]?.attentionType == .needsInput)

        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == false)
        #expect(manager.instances["s1"]?.attentionType == nil)
    }

    @Test("clearAttention resets attentionType to nil")
    @MainActor func clearAttentionWorks() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.attentionType == .needsInput)

        manager.clearAttention(for: "s1")
        #expect(manager.instances["s1"]?.attentionType == nil)
        #expect(manager.instances["s1"]?.needsAttention == false)
    }

    @Test("clearAttention with nonexistent ID is safe")
    @MainActor func clearAttentionWithNonexistentIdIsSafe() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.clearAttention(for: "nonexistent")
        #expect(manager.instances.isEmpty)
    }

    @Test("New instance has nil attentionType")
    @MainActor func newInstanceDoesNotHaveAttention() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == false)
        #expect(manager.instances["s1"]?.attentionType == nil)
    }

    @Test("Non-working to non-working does not set attention")
    @MainActor func nonWorkingToNonWorkingNoAttention() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "unknown", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == false)
    }

    @Test("Attention instance excluded from waitingInstances")
    @MainActor func attentionInstanceExcludedFromWaitingInstances() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == true)
        #expect(manager.needsAttentionInstances.count == 1)
        #expect(manager.waitingInstances.isEmpty)
    }

    @Test("needsAttentionCount is correct after transitions")
    @MainActor func needsAttentionCountIsCorrect() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/b",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.needsAttentionCount == 0)

        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.needsAttentionCount == 1)

        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/b",
            status: "unknown", tty: nil, tool: nil
        ))
        #expect(manager.needsAttentionCount == 2)
    }

    @Test("Sorted instances show attention first")
    @MainActor func sortedInstancesAttentionFirst() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/b",
            status: "processing", tty: nil, tool: nil
        ))
        // Transition s1 to waiting (sets attention)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "waiting_for_input", tty: nil, tool: nil
        ))

        let sorted = manager.sortedInstances
        #expect(sorted.count == 2)
        #expect(sorted[0].id == "s1") // Attention instance first
        #expect(sorted[0].needsAttention == true)
        #expect(sorted[1].id == "s2") // Working instance second
    }

    // MARK: - Counts

    @Test("Active/waiting/idle counts are correct")
    @MainActor func countsAreCorrect() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/b",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s3", pid: 102, cwd: "/tmp/c",
            status: "unknown", tty: nil, tool: nil
        ))
        #expect(manager.activeCount == 1)
        #expect(manager.waitingCount == 1)
        #expect(manager.idleCount == 1)
    }

    // MARK: - Attention Transitions

    @Test("Same status repeated does not set attention")
    @MainActor func sameStatusRepeatedNoAttention() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == false)
    }

    @Test("Ended removes attention instance")
    @MainActor func endedRemovesAttentionInstance() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == true)

        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "ended", tty: nil, tool: nil
        ))
        #expect(manager.instances.isEmpty)
        #expect(manager.needsAttentionCount == 0)
    }

    // MARK: - PID Deduplication

    @Test("Same PID socket events are deduplicated")
    @MainActor func samePidSocketEventsAreDeduplicated() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "subagent1", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances.count == 1)
        #expect(manager.instances["parent"] != nil)
    }

    @Test("Subagent does NOT override canonical status")
    @MainActor func subagentDoesNotOverrideCanonicalStatus() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["parent"]?.status == .working)
        #expect(manager.instances["parent"]?.needsAttention == false)

        // Subagent sends waiting_for_input — should NOT change parent status
        manager.handleSocketEvent(.init(
            sessionId: "subagent1", pid: 200, cwd: "/tmp/project",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["parent"]?.status == .working)
        #expect(manager.instances["parent"]?.needsAttention == false)
    }

    @Test("Subagent updates tool but NOT tty")
    @MainActor func subagentUpdatesToolButNotTty() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: "/dev/ttys001", tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "subagent1", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: "/dev/ttys005", tool: "Grep"
        ))
        // TTY should NOT be overwritten by subagent (fix 1.3)
        #expect(manager.instances["parent"]?.tty == "/dev/ttys001")
        // Tool should still be updated
        #expect(manager.instances["parent"]?.lastTool == "Grep")
    }

    @Test("Subagent 'ended' does not remove canonical")
    @MainActor func subagentEndedDoesNotRemoveCanonical() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "subagent1", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        // End the subagent — parent should survive
        manager.handleSocketEvent(.init(
            sessionId: "subagent1", pid: 200, cwd: "/tmp/project",
            status: "ended", tty: nil, tool: nil
        ))
        #expect(manager.instances.count == 1)
        #expect(manager.instances["parent"] != nil)
    }

    @Test("Canonical 'ended' removes instance even with subagent history")
    @MainActor func canonicalEndedRemovesInstance() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        // Subagent deduped into parent
        manager.handleSocketEvent(.init(
            sessionId: "sub1", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances.count == 1)

        // Canonical session ends
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "ended", tty: nil, tool: nil
        ))
        #expect(manager.instances.isEmpty)
    }

    @Test("Different PIDs remain separate")
    @MainActor func differentPidsRemainSeparate() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 200, cwd: "/tmp/project1",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 201, cwd: "/tmp/project2",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances.count == 2)
    }

    @Test("PID reuse after session ends creates fresh instance")
    @MainActor func pidReuseAfterSessionEndsCreatesFresh() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 200, cwd: "/tmp/project",
            status: "ended", tty: nil, tool: nil
        ))
        #expect(manager.instances.isEmpty)

        // New session reuses same PID
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances.count == 1)
        #expect(manager.instances["s2"] != nil)
    }

    @Test("Multiple subagents deduplicate to one instance")
    @MainActor func multipleSubagentsDeduplicate() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "sub1", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "sub2", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances.count == 1)
        #expect(manager.instances["parent"] != nil)
    }

    @Test("PID 0 does not cause false dedup")
    @MainActor func pidZeroDoesNotCauseFalseDedup() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 0, cwd: "/tmp/a",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 0, cwd: "/tmp/b",
            status: "processing", tty: nil, tool: nil
        ))
        // PID 0 events are rejected by the guard
        #expect(manager.instances.isEmpty)
    }

    @Test("Counts exclude attention instances")
    @MainActor func countsExcludeAttentionInstances() {
        let manager = InstanceManager(skipBootstrap: true)
        // Create a working instance
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "processing", tty: nil, tool: nil
        ))
        // Transition to waiting (sets attention)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        // Create a regular waiting instance (no attention since it starts as waiting)
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/b",
            status: "waiting_for_input", tty: nil, tool: nil
        ))

        #expect(manager.needsAttentionCount == 1)
        #expect(manager.waitingCount == 1) // Only s2, not s1
        #expect(manager.activeCount == 0)
    }

    // MARK: - Socket Event Edge Cases

    @Test("updatedAt is refreshed by subagent socket events")
    @MainActor func updatedAtRefreshedBySubagentEvents() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        let firstUpdate = manager.instances["parent"]!.updatedAt

        // Small delay to ensure time difference
        Thread.sleep(forTimeInterval: 0.01)

        manager.handleSocketEvent(.init(
            sessionId: "subagent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        let secondUpdate = manager.instances["parent"]!.updatedAt
        #expect(secondUpdate > firstUpdate)
    }

    @Test("Direct session_id match takes priority over PID match")
    @MainActor func directMatchTakesPriorityOverPidMatch() {
        let manager = InstanceManager(skipBootstrap: true)
        // Create parent instance
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        // Send event with parent's session_id — should match directly, not via PID
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        // Direct match means status transition IS applied
        #expect(manager.instances["parent"]?.status == .waitingInput)
        #expect(manager.instances["parent"]?.needsAttention == true)
    }

    @Test("Negative PID is rejected")
    @MainActor func negativePidIsRejected() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: -1, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances.isEmpty)
    }

    // MARK: - Project Name from Git Root

    @Test("projectName uses git root name when cwd is a subdirectory")
    @MainActor func projectNameUsesGitRootFromSubdirectory() throws {
        let tmp = NSTemporaryDirectory() + "InstanceManagerTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Create a git repo at tmp/my-cool-repo/.git
        let repoRoot = (tmp as NSString).appendingPathComponent("my-cool-repo")
        let gitDir = (repoRoot as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            toFile: (gitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        // Create a subdirectory
        let subDir = (repoRoot as NSString).appendingPathComponent("packages/frontend")
        try FileManager.default.createDirectory(atPath: subDir, withIntermediateDirectories: true)

        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: subDir,
            status: "processing", tty: nil, tool: nil
        ))
        // projectName should be the repo root name, not "frontend"
        #expect(manager.instances["s1"]?.projectName == "my-cool-repo")
    }

    @Test("projectName falls back to directory name when not in a git repo")
    @MainActor func projectNameFallsBackToDirectoryName() throws {
        let tmp = NSTemporaryDirectory() + "InstanceManagerTests-\(UUID().uuidString)"
        let dir = (tmp as NSString).appendingPathComponent("standalone-dir")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: dir,
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.projectName == "standalone-dir")
    }

    @Test("'ended' event with PID 0 still removes instance")
    @MainActor func endedEventWithPidZeroRemovesInstance() {
        let manager = InstanceManager(skipBootstrap: true)
        // Create instance normally
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances.count == 1)

        // Send ended event with PID 0 — should still remove (ended check is before PID guard)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 0, cwd: "/tmp/test",
            status: "ended", tty: nil, tool: nil
        ))
        #expect(manager.instances.isEmpty)
    }

    @Test("Subagent TTY does NOT overwrite canonical tty")
    @MainActor func subagentTtyDoesNotOverwriteCanonical() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: "/dev/ttys001", tool: nil
        ))
        #expect(manager.instances["parent"]?.tty == "/dev/ttys001")

        // Subagent with different TTY
        manager.handleSocketEvent(.init(
            sessionId: "subagent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: "/dev/ttys099", tool: nil
        ))
        // Parent TTY must remain unchanged
        #expect(manager.instances["parent"]?.tty == "/dev/ttys001")
    }

    // MARK: - State File Sync

    @Test("State file with parent and subagent (same PID) produces 1 instance")
    @MainActor func stateFileDedupSamePid() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        let stateFile = InstanceManager.StateFile(instances: [
            "parent": .init(status: "active", pid: 200, cwd: "/tmp/project"),
            "subagent": .init(status: "active", pid: 200, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances.count == 1)
    }

    @Test("Subagent entry in state file does not override canonical status")
    @MainActor func stateFileSubagentDoesNotOverrideStatus() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        // First establish a canonical instance via socket event
        manager.handleSocketEvent(.init(
            sessionId: "parent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["parent"]?.status == .working)

        // State file has subagent with idle status
        let stateFile = InstanceManager.StateFile(instances: [
            "parent": .init(status: "active", pid: 200, cwd: "/tmp/project"),
            "subagent": .init(status: "unknown", pid: 200, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["parent"]?.status == .working)
        #expect(manager.instances.count == 1)
    }

    @Test("State file entries with pid <= 0 are skipped")
    @MainActor func stateFileSkipsInvalidPid() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "active", pid: 0, cwd: "/tmp/a"),
            "s2": .init(status: "active", pid: -1, cwd: "/tmp/b"),
            "s3": .init(status: "active", pid: 100, cwd: "/tmp/c"),
        ])
        manager.sync(from: stateFile)
        // Only s3 should be created (valid PID)
        #expect(manager.instances.count == 1)
        #expect(manager.instances.values.first?.pid == 100)
    }

    // MARK: - Stale Threshold Guard

    @Test("Recently-updated instance survives state file removal")
    @MainActor func recentlyUpdatedInstanceSurvivesRemoval() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        // Create instance via socket event (sets updatedAt to now)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances.count == 1)

        // Sync with empty state file — instance was just updated, should survive
        manager.sync(from: InstanceManager.StateFile(instances: [:]))
        #expect(manager.instances.count == 1)
        #expect(manager.instances["s1"] != nil)
    }

    @Test("Stale instance gets removed by state file sync")
    @MainActor func staleInstanceRemovedBySync() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        // Create instance via socket event
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        // Artificially age the instance past the stale threshold
        manager.instances["s1"]!.updatedAt = Date().addingTimeInterval(-10)

        // Sync with empty state file — stale instance should be removed
        manager.sync(from: InstanceManager.StateFile(instances: [:]))
        #expect(manager.instances.isEmpty)
    }

    @Test("Instance at exact stale boundary is removed")
    @MainActor func instanceAtStaleBoundaryIsRemoved() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        // Set updatedAt to exactly 5 seconds ago (at the boundary)
        manager.instances["s1"]!.updatedAt = Date().addingTimeInterval(-5)

        manager.sync(from: InstanceManager.StateFile(instances: [:]))
        // At the boundary, instance should be removed (updatedAt is NOT > staleThreshold)
        #expect(manager.instances.isEmpty)
    }

    // MARK: - Socket Priority over State File

    @Test("Socket-set working status not overwritten by state file idle")
    @MainActor func socketStatusNotOverwrittenByStateFile() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        // Create instance via socket event (sets lastSocketEventAt)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .working)

        // Sync state file reporting 'unknown' (maps to .idle) — should not override socket status
        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "unknown", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        // Status must remain .working — socket is authoritative
        #expect(manager.instances["s1"]?.status == .working)
    }

    @Test("State file can update status for instances with no socket events")
    @MainActor func stateFileUpdatesStatusWithoutSocketEvents() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        // Create instance via state file (no socket events)
        let stateFile1 = InstanceManager.StateFile(instances: [
            "s1": .init(status: "active", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile1)
        #expect(manager.instances["s1"]?.status == .working)

        // Sync again with different status — should update normally
        let stateFile2 = InstanceManager.StateFile(instances: [
            "s1": .init(status: "waiting_for_input", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile2)
        #expect(manager.instances["s1"]?.status == .waitingInput)
    }

    @Test("New socket event instance has lastSocketEventAt set")
    @MainActor func newSocketInstanceHasLastSocketEventAt() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.lastSocketEventAt != nil)
    }

    @Test("State-file-created instance has no lastSocketEventAt")
    @MainActor func stateFileInstanceHasNoLastSocketEventAt() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "active", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["s1"]?.lastSocketEventAt == nil)
    }

    @Test("Subagent socket event does NOT set lastSocketEventAt on canonical")
    @MainActor func subagentDoesNotSetLastSocketEventAtOnCanonical() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        // Create parent via state file (naturally has no socket history)
        let stateFile = InstanceManager.StateFile(instances: [
            "parent": .init(status: "active", pid: 200, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["parent"]?.lastSocketEventAt == nil)

        // Subagent event (different session_id, same PID) — resolved via PID dedup
        manager.handleSocketEvent(.init(
            sessionId: "subagent", pid: 200, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        // Subagent event is NOT a direct match, so lastSocketEventAt should remain nil
        #expect(manager.instances["parent"]?.lastSocketEventAt == nil)
    }

    @Test("State file sync sets updatedAt on existing instances")
    @MainActor func stateFileSyncSetsUpdatedAt() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        // Create instance via socket event
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        // Age the instance
        let oldDate = Date().addingTimeInterval(-3)
        manager.instances["s1"]!.updatedAt = oldDate

        // State file sync should refresh updatedAt
        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "active", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["s1"]!.updatedAt > oldDate)
    }

    // MARK: - AttentionType-Specific Tests

    @Test("working -> waiting -> idle keeps original .needsInput attention type")
    @MainActor func workingToWaitingToIdleKeepsOriginalAttentionType() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.attentionType == .needsInput)

        // waitingInput -> idle should NOT change attentionType (non-working -> non-working)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "unknown", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.attentionType == .needsInput)
    }

    @Test("needsInputGroups filtered correctly")
    @MainActor func needsInputGroupsFilteredCorrectly() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/proj",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/proj",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/proj",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/proj",
            status: "unknown", tty: nil, tool: nil
        ))

        let inputGroups = manager.needsInputGroups
        #expect(inputGroups.flatMap(\.instances).count == 1)
        #expect(inputGroups.flatMap(\.instances).first?.id == "s1")
    }

    @Test("taskFinishedGroups filtered correctly")
    @MainActor func taskFinishedGroupsFilteredCorrectly() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/proj",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/proj",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/proj",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/proj",
            status: "unknown", tty: nil, tool: nil
        ))

        let finishedGroups = manager.taskFinishedGroups
        #expect(finishedGroups.flatMap(\.instances).count == 1)
        #expect(finishedGroups.flatMap(\.instances).first?.id == "s2")
    }

    @Test("sortedInstances orders needsInput before taskFinished")
    @MainActor func sortedInstancesOrdersNeedsInputBeforeTaskFinished() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/b",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "unknown", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/b",
            status: "waiting_for_input", tty: nil, tool: nil
        ))

        let sorted = manager.sortedInstances
        #expect(sorted[0].attentionType == .needsInput)
        #expect(sorted[1].attentionType == .taskFinished)
    }

    @Test("State file sync triggers correct attention type")
    @MainActor func stateFileSyncTriggersCorrectAttentionType() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))

        // Age the socket event so state file sync is not deferred
        manager.instances["s1"]!.lastSocketEventAt = Date().addingTimeInterval(-60)

        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "waiting_for_input", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["s1"]?.attentionType == .needsInput)

        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.attentionType == nil)

        manager.instances["s1"]!.lastSocketEventAt = Date().addingTimeInterval(-60)

        let stateFile2 = InstanceManager.StateFile(instances: [
            "s1": .init(status: "unknown", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile2)
        #expect(manager.instances["s1"]?.attentionType == .taskFinished)
    }

    // MARK: - Socket Recency Window

    @Test("Socket-to-socket transition works when socket is authoritative")
    @MainActor func socketToSocketTransitionWorks() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .working)

        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "unknown", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["s1"]?.status == .working)

        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .waitingInput)
        #expect(manager.instances["s1"]?.needsAttention == true)
    }

    @Test("Removed and recreated instance starts with no socket history")
    @MainActor func removedAndRecreatedInstanceStartsFresh() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.lastSocketEventAt != nil)

        manager.instances["s1"]!.updatedAt = Date().addingTimeInterval(-10)

        manager.sync(from: InstanceManager.StateFile(instances: [:]))
        #expect(manager.instances.isEmpty)

        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "waiting_for_input", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["s1"]?.lastSocketEventAt == nil)
        #expect(manager.instances["s1"]?.status == .waitingInput)
    }

    @Test("State-file instance becomes socket-managed on first socket event")
    @MainActor func stateFileInstanceBecomesSocketManaged() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        let stateFile1 = InstanceManager.StateFile(instances: [
            "s1": .init(status: "active", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile1)
        #expect(manager.instances["s1"]?.lastSocketEventAt == nil)

        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.lastSocketEventAt != nil)

        let stateFile2 = InstanceManager.StateFile(instances: [
            "s1": .init(status: "waiting_for_input", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile2)
        #expect(manager.instances["s1"]?.status == .working)
    }

    @Test("updatedAt refreshed even when socket status blocks state file update")
    @MainActor func updatedAtRefreshedWhenSocketBlocks() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        let oldDate = Date().addingTimeInterval(-1)
        manager.instances["s1"]!.updatedAt = oldDate

        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "unknown", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["s1"]?.status == .working)
        #expect(manager.instances["s1"]!.updatedAt > oldDate)
    }

    @Test("State file regains authority after socket recency expires")
    @MainActor func stateFileRegainsAuthorityAfterRecencyExpires() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .working)

        manager.instances["s1"]!.lastSocketEventAt = Date().addingTimeInterval(
            -(InstanceManager.socketRecencyWindow + 1)
        )

        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "unknown", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["s1"]?.status == .idle)
    }

    // MARK: - Socket Grace Window Suppression

    @Test("State file sync defers to recent socket event")
    @MainActor func stateFileSyncDefersToRecentSocketEvent() {
        InstanceManager.testProcessAliveOverride = { _ in true }
        defer { InstanceManager.testProcessAliveOverride = nil }

        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/project",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .working)

        let stateFile = InstanceManager.StateFile(instances: [
            "s1": .init(status: "waiting_for_input", pid: 100, cwd: "/tmp/project"),
        ])
        manager.sync(from: stateFile)
        #expect(manager.instances["s1"]?.attentionType == nil)
        #expect(manager.instances["s1"]?.status == .working)
    }

    // MARK: - Attention Type Coverage

    @Test("Working to waiting_for_approval sets attentionType .needsInput")
    @MainActor func workingToWaitingForApprovalSetsNeedsInput() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_approval", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.attentionType == .needsInput)
    }

    @Test("clearAttention resets .taskFinished attentionType to nil")
    @MainActor func clearAttentionOnTaskFinished() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "unknown", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.attentionType == .taskFinished)

        manager.clearAttention(for: "s1")
        #expect(manager.instances["s1"]?.attentionType == nil)
        #expect(manager.instances["s1"]?.needsAttention == false)
    }

    // MARK: - TerminalFocusMonitor Eligibility

    @Test("Attention set recently is NOT eligible for clearing")
    @MainActor func recentAttentionNotEligible() {
        let instance = ClaudeInstance(id: "s1", pid: 100, cwd: "/tmp/test", status: .working)
        instance.transition(to: .waitingInput)
        #expect(instance.attentionSetAt != nil)

        let now = Date()
        #expect(!TerminalFocusMonitor.isEligibleForClearing(instance, at: now))
    }

    @Test("Attention set long ago IS eligible for clearing")
    @MainActor func oldAttentionIsEligible() {
        let instance = ClaudeInstance(id: "s1", pid: 100, cwd: "/tmp/test", status: .working)
        instance.transition(to: .waitingInput)

        let future = Date().addingTimeInterval(TerminalFocusMonitor.attentionGracePeriod + 1)
        #expect(TerminalFocusMonitor.isEligibleForClearing(instance, at: future))
    }

    @Test("Nil attentionSetAt IS eligible for clearing")
    @MainActor func nilAttentionSetAtIsEligible() {
        let instance = ClaudeInstance(id: "s1", pid: 100, cwd: "/tmp/test")
        #expect(instance.attentionSetAt == nil)
        #expect(TerminalFocusMonitor.isEligibleForClearing(instance, at: Date()))
    }
}
