import Foundation
import Testing
@testable import ClaudeNotch

@Suite("ProcessScanner Tests")
struct ProcessScannerTests {

    @Test("Scan returns injected mock processes")
    func scanReturnsMockProcesses() {
        ProcessScanner.testOverride = {
            [
                (pid: 100, cwd: "/tmp/project-a"),
                (pid: 200, cwd: "/tmp/project-b"),
            ]
        }
        defer { ProcessScanner.testOverride = nil }

        let scanner = ProcessScanner()
        let results = scanner.scan()
        #expect(results.count == 2)
        #expect(results[0].pid == 100)
        #expect(results[0].cwd == "/tmp/project-a")
        #expect(results[1].pid == 200)
        #expect(results[1].cwd == "/tmp/project-b")
    }

    @Test("Scan returns empty when no mock processes")
    func scanReturnsEmptyWithNoMocks() {
        ProcessScanner.testOverride = { [] }
        defer { ProcessScanner.testOverride = nil }

        let scanner = ProcessScanner()
        let results = scanner.scan()
        #expect(results.isEmpty)
    }

    @Test("Scan interval is 10 seconds")
    func scanIntervalIs10Seconds() {
        #expect(ProcessScanner.scanInterval == 10)
    }
}
