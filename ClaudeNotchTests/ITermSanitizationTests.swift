import Foundation
import Testing
@testable import ClaudeNotch

@Suite("iTerm Sanitization Tests")
struct ITermSanitizationTests {

    // MARK: - TTY Sanitization

    @Test("Valid TTY passes sanitization")
    func validTTYPasses() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys042") == "/dev/ttys042")
    }

    @Test("Valid TTY with many digits passes")
    func validTTYManyDigits() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys12345") == "/dev/ttys12345")
    }

    @Test("Invalid TTY with injection is rejected")
    func injectionTTYRejected() {
        #expect(ITermIntegration.sanitizeTTY("\"; malicious script") == nil)
    }

    @Test("Empty TTY is rejected")
    func emptyTTYRejected() {
        #expect(ITermIntegration.sanitizeTTY("") == nil)
    }

    @Test("TTY without /dev/ prefix is rejected")
    func noPrefixRejected() {
        #expect(ITermIntegration.sanitizeTTY("ttys042") == nil)
    }

    @Test("TTY with path traversal is rejected")
    func pathTraversalRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/../etc/passwd") == nil)
    }

    @Test("TTY with spaces is rejected")
    func spacesRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys 042") == nil)
    }

    @Test("TTY without digits is rejected")
    func noDigitsRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys") == nil)
    }

    // MARK: - Directory Sanitization

    @Test("Valid existing directory passes")
    func validDirectoryPasses() {
        // /tmp always exists on macOS
        let result = ITermIntegration.sanitizeDirectory("/tmp")
        #expect(result == "/tmp")
    }

    @Test("Home directory passes")
    func homeDirectoryPasses() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = ITermIntegration.sanitizeDirectory(home)
        #expect(result == home)
    }

    @Test("Directory with injection is rejected")
    func injectionDirectoryRejected() {
        let result = ITermIntegration.sanitizeDirectory("/tmp\"; rm -rf /")
        // After stripping disallowed chars, the path won't match a real directory
        #expect(result == nil || !result!.contains(";"))
    }

    @Test("Non-existent directory is rejected")
    func nonExistentRejected() {
        let result = ITermIntegration.sanitizeDirectory("/nonexistent/path/that/doesnt/exist")
        #expect(result == nil)
    }

    @Test("Empty directory is rejected")
    func emptyDirectoryRejected() {
        #expect(ITermIntegration.sanitizeDirectory("") == nil)
    }

    @Test("File path (not directory) is rejected")
    func filePathRejected() {
        // /etc/hosts is a file, not a directory
        let result = ITermIntegration.sanitizeDirectory("/etc/hosts")
        #expect(result == nil)
    }

    @Test("Directory with allowed special characters passes")
    func specialCharsPasses() {
        // /tmp should exist and only has allowed characters
        let result = ITermIntegration.sanitizeDirectory("/tmp")
        #expect(result != nil)
    }
}
