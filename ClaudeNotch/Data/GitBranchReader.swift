import Foundation

/// Reads git information by walking up from a given directory to find the nearest .git entry,
/// then parsing HEAD and config files. Handles regular repos, worktrees, and detached HEAD.
struct GitBranchReader: Sendable {

    /// Returns the current branch name, or the first 7 chars of the SHA for detached HEAD.
    /// Returns nil if no enclosing git repo is found or the HEAD file cannot be read.
    func readBranch(forDirectory cwd: String) -> String? {
        guard let git = findGitPath(from: cwd) else { return nil }
        let gitRoot = (git.path as NSString).deletingLastPathComponent

        let headPath: String
        if git.isDirectory {
            // Regular repo: .git is a directory
            headPath = (git.path as NSString).appendingPathComponent("HEAD")
        } else {
            // Worktree: .git is a file containing "gitdir: <path>"
            guard let gitFileContent = readFileString(atPath: git.path),
                  let gitdir = parseGitdir(gitFileContent, relativeTo: gitRoot) else {
                return nil
            }
            headPath = (gitdir as NSString).appendingPathComponent("HEAD")
        }

        guard let headContent = readFileString(atPath: headPath) else {
            return nil
        }

        return parseBranch(from: headContent)
    }

    /// Returns the origin remote URL for the nearest enclosing git repo.
    /// Handles regular repos and worktrees (follows `commondir` to the main `.git`).
    func readRemoteURL(forDirectory cwd: String) -> String? {
        guard let git = findGitPath(from: cwd) else { return nil }
        let gitRoot = (git.path as NSString).deletingLastPathComponent

        let configPath: String
        if git.isDirectory {
            configPath = (git.path as NSString).appendingPathComponent("config")
        } else {
            // Worktree — follow gitdir, then commondir to find the main .git/config
            guard let gitFileContent = readFileString(atPath: git.path),
                  let gitdir = parseGitdir(gitFileContent, relativeTo: gitRoot) else {
                return nil
            }
            let commondirFile = (gitdir as NSString).appendingPathComponent("commondir")
            if let commondirContent = readFileString(atPath: commondirFile) {
                let mainGitDir: String
                if commondirContent.hasPrefix("/") {
                    mainGitDir = commondirContent
                } else {
                    let resolved = (gitdir as NSString).appendingPathComponent(commondirContent)
                    mainGitDir = (resolved as NSString).standardizingPath
                }
                configPath = (mainGitDir as NSString).appendingPathComponent("config")
            } else {
                configPath = (gitdir as NSString).appendingPathComponent("config")
            }
        }

        guard let configContent = readFileString(atPath: configPath) else {
            return nil
        }

        return parseOriginURL(from: configContent)
    }

    /// Extracts the repo name from a remote URL (last path component, stripped of `.git`).
    static func repoName(from remoteURL: String) -> String? {
        // Handle both SSH (git@host:user/repo.git) and HTTPS (https://host/user/repo.git)
        let path: String
        if let colonRange = remoteURL.range(of: ":", options: .backwards),
           !remoteURL[remoteURL.startIndex..<colonRange.lowerBound].contains("/") {
            // SSH format: git@github.com:user/repo.git
            path = String(remoteURL[colonRange.upperBound...])
        } else {
            path = remoteURL
        }
        var name = (path as NSString).lastPathComponent
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }
        return name.isEmpty ? nil : name
    }

    /// Walks up the directory tree to find the nearest `.git` entry and returns its parent.
    /// Returns `nil` if no `.git` is found (not a git repo).
    func gitRootDirectory(from directory: String) -> String? {
        guard let git = findGitPath(from: directory) else { return nil }
        return (git.path as NSString).deletingLastPathComponent
    }

    // MARK: - Private

    /// Walks up from `directory` to find the nearest `.git` entry (file or directory).
    /// Returns the path and whether it is a directory.
    private func findGitPath(from directory: String) -> (path: String, isDirectory: Bool)? {
        guard !directory.isEmpty else { return nil }
        let fm = FileManager.default
        var current = directory
        while true {
            let gitPath = (current as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitPath, isDirectory: &isDir) {
                return (path: gitPath, isDirectory: isDir.boolValue)
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return nil
    }

    private func readFileString(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses `gitdir: <path>` from a `.git` file and resolves relative paths.
    private func parseGitdir(_ content: String, relativeTo base: String) -> String? {
        guard content.hasPrefix("gitdir: ") else { return nil }
        let rawPath = String(content.dropFirst("gitdir: ".count))

        if rawPath.hasPrefix("/") {
            return rawPath
        }
        // Relative path — resolve against base (the directory containing the .git entry)
        let resolved = (base as NSString).appendingPathComponent(rawPath)
        return (resolved as NSString).standardizingPath
    }

    /// Parses the `[remote "origin"]` section of a git config to extract the URL.
    private func parseOriginURL(from config: String) -> String? {
        let lines = config.components(separatedBy: .newlines)
        var inOriginSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inOriginSection = trimmed == "[remote \"origin\"]"
                continue
            }
            if inOriginSection, trimmed.hasPrefix("url") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
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
