import Foundation

struct ProjectGroup: Identifiable {
    let groupKey: String
    let displayName: String
    let instances: [ClaudeInstance]
    var id: String { groupKey }
    var count: Int { instances.count }
    var isSingle: Bool { instances.count == 1 }
}
