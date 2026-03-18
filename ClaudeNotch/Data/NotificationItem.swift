import Foundation

struct NotificationItem: Identifiable {
    let instanceId: String
    let projectName: String
    let branchName: String?
    let terminalIndex: Int?
    let tty: String?
    let pid: Int
    var id: String { instanceId }

    func withTerminalIndex(_ index: Int) -> NotificationItem {
        NotificationItem(
            instanceId: instanceId,
            projectName: projectName,
            branchName: branchName,
            terminalIndex: index,
            tty: tty,
            pid: pid
        )
    }
}
