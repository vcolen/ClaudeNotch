import Foundation

enum RecentProjectsStore {

    private static let key = "recentProjects"

    static func addProject(_ path: String) {
        var projects = UserDefaults.standard.stringArray(forKey: key) ?? []
        projects.removeAll { $0 == path }
        projects.insert(path, at: 0)
        if projects.count > 20 {
            projects = Array(projects.prefix(20))
        }
        UserDefaults.standard.set(projects, forKey: key)
    }

    static var recentProjects: [String] {
        let projects = UserDefaults.standard.stringArray(forKey: key) ?? []
        return projects.filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
