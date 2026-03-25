import Foundation

/// Scans for running Claude processes by inspecting the system process list.
///
/// In production, uses `pgrep` + `/proc`-style lookups to discover Claude CLI
/// processes and their working directories. In tests, the `testOverride` closure
/// can inject synthetic process data.
final class ProcessScanner: Sendable {

    struct DiscoveredProcess: Sendable {
        let pid: Int
        let cwd: String
    }

    static let scanInterval: TimeInterval = 10

    /// Test-only hook: when non-nil, `scan()` returns the result of this closure
    /// instead of querying real processes.
    nonisolated(unsafe) static var testOverride: (() -> [(pid: Int, cwd: String)])?

    func scan() -> [DiscoveredProcess] {
        if let override = Self.testOverride {
            return override().map { DiscoveredProcess(pid: $0.pid, cwd: $0.cwd) }
        }

        // Discover running `claude` processes via pgrep
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results = [DiscoveredProcess]()
        for line in output.split(separator: "\n") {
            guard let pid = Int(line.trimmingCharacters(in: .whitespaces)) else { continue }
            guard let cwd = workingDirectory(for: pid) else { continue }
            results.append(DiscoveredProcess(pid: pid, cwd: cwd))
        }
        return results
    }

    private func workingDirectory(for pid: Int) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // lsof -Fn outputs lines like "n/path/to/dir"
        for line in output.split(separator: "\n") {
            if line.hasPrefix("n/") {
                return String(line.dropFirst(1))
            }
        }
        return nil
    }
}
