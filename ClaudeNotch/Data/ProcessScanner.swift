import Foundation
import Darwin

/// Scans the process table for running Claude instances as a fallback data source.
/// Runs off the main actor since it performs I/O-bound syscalls.
final class ProcessScanner: @unchecked Sendable {

    static let scanInterval: TimeInterval = 10

    #if DEBUG
    nonisolated(unsafe) static var testOverride: (() -> [(pid: Int, cwd: String)])?
    #endif

    struct DiscoveredProcess: Sendable {
        let pid: Int
        let cwd: String
    }

    /// Scans the process table and returns PIDs + CWDs of running Claude processes.
    func scan() -> [DiscoveredProcess] {
        #if DEBUG
        if let override = Self.testOverride {
            return override().map { DiscoveredProcess(pid: $0.pid, cwd: $0.cwd) }
        }
        #endif

        // Phase 1: Get all PIDs (cheap bulk syscall)
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }

        var pids = [Int32](repeating: 0, count: Int(pidCount) + 64)
        let actualCount = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<Int32>.size))
        }
        guard actualCount > 0 else { return [] }

        var results: [DiscoveredProcess] = []
        var pathBuffer = [CChar](repeating: 0, count: 4096)

        // Phase 2: Filter by executable path
        for i in 0..<Int(actualCount) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard pathLength > 0 else { continue }

            let path = String(cString: pathBuffer)

            let isClaude: Bool
            if path.contains("claude") {
                isClaude = true
            } else if path.contains("node") {
                // Phase 3: For node processes, check command-line args
                isClaude = isClaudeNode(pid: pid)
            } else {
                continue
            }

            guard isClaude else { continue }

            // Phase 4: Get CWD for confirmed Claude processes
            if let cwd = processCwd(pid: pid) {
                results.append(DiscoveredProcess(pid: Int(pid), cwd: cwd))
            }
        }

        return results
    }

    /// Checks if a node process is running Claude by inspecting command-line args.
    private func isClaudeNode(pid: Int32) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0

        // First call to get buffer size
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return false }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }

        guard sysctl(&mib, 3, buffer, &size, nil, 0) == 0 else { return false }

        // Skip argc (first 4 bytes), then scan the args as a string
        guard size > MemoryLayout<Int32>.size else { return false }
        let argsStart = buffer.advanced(by: MemoryLayout<Int32>.size)
        let argsLength = size - MemoryLayout<Int32>.size

        // Convert to string for simple matching
        let argsData = Data(bytes: argsStart, count: argsLength)
        guard let argsString = String(data: argsData, encoding: .utf8) else { return false }

        return argsString.contains("claude")
    }

    /// Gets the current working directory of a process via proc_pidinfo.
    private func processCwd(pid: Int32) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, Int32(size))
        guard result == size else { return nil }

        return withUnsafePointer(to: vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cPath in
                let path = String(cString: cPath)
                return path.isEmpty ? nil : path
            }
        }
    }
}
