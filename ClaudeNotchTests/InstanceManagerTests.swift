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

    @Test("Sorted instances ordered by updatedAt descending")
    func sortedInstancesOrder() {
        let manager = InstanceManager(skipBootstrap: true)
        manager.handleSocketEvent(.init(
            sessionId: "s1", pid: 100, cwd: "/tmp/a",
            status: "processing", tty: nil, tool: nil
        ))
        // Manually set earlier date on first instance
        manager.instances["s1"]?.updatedAt = Date.distantPast
        manager.handleSocketEvent(.init(
            sessionId: "s2", pid: 101, cwd: "/tmp/b",
            status: "waiting_for_input", tty: nil, tool: nil
        ))
        let sorted = manager.sortedInstances
        #expect(sorted.count == 2)
        #expect(sorted.first?.id == "s2") // Most recent first
    }

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
}
