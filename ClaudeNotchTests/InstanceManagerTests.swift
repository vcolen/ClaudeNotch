import Foundation
import Testing
@testable import ClaudeNotch

@MainActor
@Suite("InstanceManager Tests")
struct InstanceManagerTests {

    // MARK: - Status Mapping

    @Test("Socket event 'processing' maps to .working")
    func processingMapsToWorking() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .working)
    }

    @Test("Socket event 'running_tool' maps to .working")
    func runningToolMapsToWorking() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "running_tool", tty: nil, tool: "Bash"
        ))
        #expect(manager.instances["s1"]?.status == .working)
        #expect(manager.instances["s1"]?.lastTool == "Bash")
    }

    @Test("Socket event 'compacting' maps to .working")
    func compactingMapsToWorking() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "compacting", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .working)
    }

    @Test("Socket event 'waiting_for_input' maps to .waitingInput")
    func waitingForInputMapsToWaiting() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .waitingInput)
    }

    @Test("Socket event 'waiting_for_approval' maps to .waitingInput")
    func waitingForApprovalMapsToWaiting() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_approval", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .waitingInput)
    }

    @Test("Unknown status maps to .idle")
    func unknownMapsToIdle() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "something_else", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.status == .idle)
    }

    // MARK: - Instance Lifecycle

    @Test("New socket event creates instance")
    func newEventCreatesInstance() {
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
    func eventUpdatesExisting() {
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
    func endedRemovesInstance() {
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
    func sortedInstancesOrder() {
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
    func sameProjectGrouped() {
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
    func differentProjectsSortedAlphabetically() {
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
    func singleInstanceGroupIsSingle() {
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
    func instancesSortedByBranch() {
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
    func remoteURLGrouping() {
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

    @Test("Working to waiting sets needsAttention")
    func workingToWaitingSetsAttention() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == false)

        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == true)
    }

    @Test("Working to idle sets needsAttention")
    func workingToIdleSetsAttention() {
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
    }

    @Test("Resuming work clears needsAttention")
    func resumingWorkClearsAttention() {
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
            status: "processing", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == false)
    }

    @Test("clearAttention works")
    func clearAttentionWorks() {
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

        manager.clearAttention(for: "s1")
        #expect(manager.instances["s1"]?.needsAttention == false)
    }

    @Test("clearAttention with nonexistent ID is safe")
    func clearAttentionWithNonexistentIdIsSafe() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.clearAttention(for: "nonexistent")
        #expect(manager.instances.isEmpty)
    }

    @Test("New instance does not have attention")
    func newInstanceDoesNotHaveAttention() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/test",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        #expect(manager.instances["s1"]?.needsAttention == false)
    }

    @Test("Non-working to non-working does not set attention")
    func nonWorkingToNonWorkingNoAttention() {
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
    func attentionInstanceExcludedFromWaitingInstances() {
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
    func needsAttentionCountIsCorrect() {
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
    func sortedInstancesAttentionFirst() {
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
    func countsAreCorrect() {
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
    func sameStatusRepeatedNoAttention() {
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
    func endedRemovesAttentionInstance() {
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

    @Test("Counts exclude attention instances")
    func countsExcludeAttentionInstances() {
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

    @Test("needsAttentionGroups groups correctly")
    func needsAttentionGroupsCorrect() {
        let manager = InstanceManager(skipBootstrap: true)
        // Two instances in same project
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/proj",
            status: "processing", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/proj",
            status: "processing", tty: nil, tool: nil
        ))
        // Transition both to waiting (sets attention)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/proj",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/proj",
            status: "waiting_for_input", tty: nil, tool: nil
        ))

        let groups = manager.needsAttentionGroups
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
        #expect(groups[0].displayName == "proj")
    }
}
