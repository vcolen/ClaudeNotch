import Foundation

/// Reads the current git branch from a working directory by parsing `.git/HEAD`.
/// Handles regular repos, worktrees (`.git` file with `gitdir:` pointer), and detached HEAD.
struct GitBranchReader: Sendable {

    /// Returns the current branch name, or the first 7 chars of the SHA for detached HEAD.
    /// Returns `nil` if the directory is not a git repo or the HEAD file cannot be read.
    func readBranch(forDirectory cwd: String) -> String? {
        let fm = FileManager.default
        let gitPath = (cwd as NSString).appendingPathComponent(".git")

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: gitPath, isDirectory: &isDirectory) else {
            return nil
        }

        let headPath: String
        if isDirectory.boolValue {
            // Regular repo: .git is a directory
            headPath = (gitPath as NSString).appendingPathComponent("HEAD")
        } else {
            // Worktree: .git is a file containing "gitdir: <path>"
            guard let gitFileContent = readFileString(atPath: gitPath),
                  let gitdir = parseGitdir(gitFileContent, relativeTo: cwd) else {
                return nil
            }
            headPath = (gitdir as NSString).appendingPathComponent("HEAD")
        }

        guard let headContent = readFileString(atPath: headPath) else {
            return nil
        }

        return parseBranch(from: headContent)
    }

    // MARK: - Private

    private func readFileString(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses `gitdir: <path>` from a `.git` file and resolves relative paths.
    private func parseGitdir(_ content: String, relativeTo cwd: String) -> String? {
        guard content.hasPrefix("gitdir: ") else { return nil }
        let rawPath = String(content.dropFirst("gitdir: ".count))

        if rawPath.hasPrefix("/") {
            return rawPath
        }
        // Relative path — resolve against cwd
        let resolved = (cwd as NSString).appendingPathComponent(rawPath)
        return (resolved as NSString).standardizingPath
    }

    /// Extracts the branch name from HEAD content.
    private func parseBranch(from head: String) -> String? {
        if head.hasPrefix("ref: refs/heads/") {
            return String(head.dropFirst("ref: refs/heads/".count))
        }
        if head.hasPrefix("ref: ") {
            // Unusual ref outside refs/heads/ — return last path component
            let refPath = String(head.dropFirst("ref: ".count))
            return (refPath as NSString).lastPathComponent
        }
        // Detached HEAD — raw SHA
        guard head.count >= 7 else { return nil }
        return String(head.prefix(7))
    }
}
