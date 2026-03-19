import Foundation
import Observation

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
    var status: InstanceStatus
    var updatedAt: Date
    var tty: String?
    var cost: Double?
    var model: String?
    var contextUsagePercent: Double? // 0.0 to 1.0, capped
    var lastTool: String?
    var branchName: String?
    var remoteURL: String?
    var needsAttention: Bool = false

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
}
