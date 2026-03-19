import Foundation
import Observation

enum AttentionType: String, CaseIterable, Comparable, Sendable {
    case needsInput     // triggered by: working -> waitingInput
    case taskFinished   // triggered by: working -> any non-working state except waitingInput

    static func < (lhs: AttentionType, rhs: AttentionType) -> Bool {
        guard let lhsIdx = allCases.firstIndex(of: lhs),
              let rhsIdx = allCases.firstIndex(of: rhs) else { return false }
        return lhsIdx < rhsIdx
    }
}

enum InstanceStatus: String, Sendable {
    case working
    case waitingInput
    case idle

    var displayName: String {
        switch self {
        case .working: return "Working"
        case .waitingInput: return "Waiting"
        case .idle: return "Idle"
        }
    }
}

@Observable
final class ClaudeInstance: Identifiable, @unchecked Sendable {
    let id: String // session UUID
    var pid: Int
    var cwd: String
    var projectName: String
    private(set) var status: InstanceStatus
    var updatedAt: Date
    var tty: String?
    var cost: Double?
    var model: String?
    var contextUsagePercent: Double? // 0.0 to 1.0, capped
    var lastTool: String?
    var branchName: String?
    var remoteURL: String?
    private(set) var attentionType: AttentionType?
    /// Timestamp when attentionType was last set to a non-nil value.
    /// Used by TerminalFocusMonitor (grace period before auto-clearing)
    /// and state-file sync (to avoid suppressing recent attention).
    private(set) var attentionSetAt: Date?
    var needsAttention: Bool { attentionType != nil }
    /// Timestamp of the last socket event for this instance.
    /// Used by state-file sync (defers to recent socket events within a grace window)
    /// and TerminalFocusMonitor (factors into attention eligibility).
    var lastSocketEventAt: Date?

    init(
        id: String,
        pid: Int,
        cwd: String,
        status: InstanceStatus = .idle,
        tty: String? = nil
    ) {
        self.id = id
        self.pid = pid
        self.cwd = cwd
        self.projectName = (cwd as NSString).lastPathComponent
        self.status = status
        self.updatedAt = Date()
        self.tty = tty
    }

    /// Encapsulates status and attention state transitions.
    /// attentionType is set when leaving .working and cleared when entering .working.
    /// It intentionally persists across non-working transitions (e.g. waitingInput -> idle)
    /// so the notification stays visible until the user explicitly clears it.
    func transition(to newStatus: InstanceStatus) {
        let previousStatus = status
        status = newStatus
        if previousStatus == .working && newStatus != .working {
            attentionType = (newStatus == .waitingInput) ? .needsInput : .taskFinished
            attentionSetAt = Date()
        } else if newStatus == .working {
            attentionType = nil
            attentionSetAt = nil
        }
    }

    func clearAttention() {
        attentionType = nil
        attentionSetAt = nil
    }
}
