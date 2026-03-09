import Foundation
import Testing
@testable import ClaudeNotch

@Suite("GitBranchReader Tests")
struct GitBranchReaderTests {
    private let reader = GitBranchReader()

    // MARK: - Regular Repo

    @Test("Regular repo with branch ref returns branch name")
    func regularRepoWithBranch() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        // Create .git directory with HEAD file
        let gitDir = (tmp as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            toFile: (gitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        #expect(reader.readBranch(forDirectory: tmp) == "main")
    }

    @Test("Branch with slashes returns full name")
    func branchWithSlashes() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        let gitDir = (tmp as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/feature/add-login\n".write(
            toFile: (gitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        #expect(reader.readBranch(forDirectory: tmp) == "feature/add-login")
    }

    @Test("Detached HEAD returns first 7 chars of SHA")
    func detachedHead() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        let gitDir = (tmp as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try "abc1234def5678901234567890abcdef12345678\n".write(
            toFile: (gitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        #expect(reader.readBranch(forDirectory: tmp) == "abc1234")
    }

    // MARK: - Worktree

    @Test("Worktree with absolute gitdir path returns branch")
    func worktreeAbsolutePath() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        // Create the actual gitdir somewhere else
        let actualGitDir = (tmp as NSString).appendingPathComponent("actual-gitdir")
        try FileManager.default.createDirectory(atPath: actualGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/feature/worktree-branch\n".write(
            toFile: (actualGitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        // Create worktree directory with .git file
        let worktreeDir = (tmp as NSString).appendingPathComponent("worktree")
        try FileManager.default.createDirectory(atPath: worktreeDir, withIntermediateDirectories: true)
        try "gitdir: \(actualGitDir)\n".write(
            toFile: (worktreeDir as NSString).appendingPathComponent(".git"),
            atomically: true, encoding: .utf8
        )

        #expect(reader.readBranch(forDirectory: worktreeDir) == "feature/worktree-branch")
    }

    @Test("Worktree with relative gitdir path resolves correctly")
    func worktreeRelativePath() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        // Create .git/worktrees/my-wt directory structure
        let mainGitDir = (tmp as NSString).appendingPathComponent("main-repo/.git/worktrees/my-wt")
        try FileManager.default.createDirectory(atPath: mainGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/develop\n".write(
            toFile: (mainGitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        // Create worktree with relative .git file
        let worktreeDir = (tmp as NSString).appendingPathComponent("worktree-dir")
        try FileManager.default.createDirectory(atPath: worktreeDir, withIntermediateDirectories: true)

        let relativePath = "../main-repo/.git/worktrees/my-wt"
        try "gitdir: \(relativePath)\n".write(
            toFile: (worktreeDir as NSString).appendingPathComponent(".git"),
            atomically: true, encoding: .utf8
        )

        #expect(reader.readBranch(forDirectory: worktreeDir) == "develop")
    }

    // MARK: - Edge Cases

    @Test("Not a git repo returns nil")
    func notAGitRepo() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        #expect(reader.readBranch(forDirectory: tmp) == nil)
    }

    @Test("Non-existent directory returns nil")
    func nonExistentDirectory() {
        #expect(reader.readBranch(forDirectory: "/nonexistent/path/that/does/not/exist") == nil)
    }

    @Test("Unusual ref outside refs/heads returns last component")
    func unusualRef() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        let gitDir = (tmp as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try "ref: refs/remotes/origin/main\n".write(
            toFile: (gitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        #expect(reader.readBranch(forDirectory: tmp) == "main")
    }

    // MARK: - Helpers

    private func makeTempDir() -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("GitBranchReaderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
