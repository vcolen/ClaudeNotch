import Foundation

struct NotificationItem: Identifiable {
    let instanceId: String
    let projectName: String
    let branchName: String?
    var terminalIndex: Int?
    let tty: String?
    let pid: Int
    let attentionType: AttentionType
    var id: String { instanceId }
}
