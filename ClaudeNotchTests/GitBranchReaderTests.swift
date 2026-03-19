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

    @Test("Empty directory string returns nil")
    func emptyDirectoryReturnsNil() {
        #expect(reader.readBranch(forDirectory: "") == nil)
        #expect(reader.readRemoteURL(forDirectory: "") == nil)
        #expect(reader.gitRootDirectory(from: "") == nil)
    }

    // MARK: - gitRootDirectory

    @Test("gitRootDirectory from subdirectory returns correct root")
    func gitRootFromSubdirectory() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        // Create repo root with .git
        let gitDir = (tmp as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)

        // Create a subdirectory
        let subDir = (tmp as NSString).appendingPathComponent("packages/frontend")
        try FileManager.default.createDirectory(atPath: subDir, withIntermediateDirectories: true)

        #expect(reader.gitRootDirectory(from: subDir) == tmp)
    }

    @Test("gitRootDirectory from the root itself returns same directory")
    func gitRootFromRootItself() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        let gitDir = (tmp as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)

        #expect(reader.gitRootDirectory(from: tmp) == tmp)
    }

    @Test("gitRootDirectory from a non-git directory returns nil")
    func gitRootFromNonGitDir() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        #expect(reader.gitRootDirectory(from: tmp) == nil)
    }

    // MARK: - readBranch / readRemoteURL from subdirectory

    @Test("readBranch from a subdirectory finds branch correctly")
    func readBranchFromSubdirectory() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        let gitDir = (tmp as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/feature/deep\n".write(
            toFile: (gitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        let subDir = (tmp as NSString).appendingPathComponent("src/lib/utils")
        try FileManager.default.createDirectory(atPath: subDir, withIntermediateDirectories: true)

        #expect(reader.readBranch(forDirectory: subDir) == "feature/deep")
    }

    @Test("readRemoteURL from a subdirectory finds remote correctly")
    func readRemoteURLFromSubdirectory() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        let gitDir = (tmp as NSString).appendingPathComponent(".git")
        try FileManager.default.createDirectory(atPath: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            toFile: (gitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )
        try """
        [core]
        \trepositoryformatversion = 0
        [remote "origin"]
        \turl = git@github.com:user/my-repo.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        """.write(
            toFile: (gitDir as NSString).appendingPathComponent("config"),
            atomically: true, encoding: .utf8
        )

        let subDir = (tmp as NSString).appendingPathComponent("packages/core")
        try FileManager.default.createDirectory(atPath: subDir, withIntermediateDirectories: true)

        #expect(reader.readRemoteURL(forDirectory: subDir) == "git@github.com:user/my-repo.git")
    }

    // MARK: - Worktree relative path resolution from parent directory

    @Test("Worktree with relative gitdir resolves against git root, not cwd")
    func worktreeRelativePathResolvesAgainstGitRoot() throws {
        let tmp = makeTempDir()
        defer { cleanup(tmp) }

        // Create main repo: tmp/repo/.git/worktrees/wt1/
        let repoRoot = (tmp as NSString).appendingPathComponent("repo")
        let mainGitDir = (repoRoot as NSString).appendingPathComponent(".git")
        let worktreeGitDir = (mainGitDir as NSString).appendingPathComponent("worktrees/wt1")
        try FileManager.default.createDirectory(atPath: worktreeGitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/wt-branch\n".write(
            toFile: (worktreeGitDir as NSString).appendingPathComponent("HEAD"),
            atomically: true, encoding: .utf8
        )

        // Create worktree: tmp/wt1/ with .git file pointing relatively to repo
        let worktreeRoot = (tmp as NSString).appendingPathComponent("wt1")
        try FileManager.default.createDirectory(atPath: worktreeRoot, withIntermediateDirectories: true)
        // Relative from wt1/ to repo/.git/worktrees/wt1 (must go up one level)
        try "gitdir: ../repo/.git/worktrees/wt1\n".write(
            toFile: (worktreeRoot as NSString).appendingPathComponent(".git"),
            atomically: true, encoding: .utf8
        )

        // Read from a subdirectory of the worktree
        let subDir = (worktreeRoot as NSString).appendingPathComponent("src/deep")
        try FileManager.default.createDirectory(atPath: subDir, withIntermediateDirectories: true)

        // This tests fix 1.1: the relative gitdir path must resolve against the
        // directory containing .git (wt1/), not the original cwd (wt1/src/deep/)
        #expect(reader.readBranch(forDirectory: subDir) == "wt-branch")
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
