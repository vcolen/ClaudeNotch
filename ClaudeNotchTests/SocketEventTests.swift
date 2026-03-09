import Foundation
import Testing
@testable import ClaudeNotch

@Suite("Socket Event Tests")
struct SocketEventTests {

    // MARK: - Event Parsing

    @Test("Valid JSON event parses all fields")
    func validJsonParsesAllFields() throws {
        let json = """
        {
            "session_id": "abc-123",
            "pid": 42,
            "cwd": "/Users/test/project",
            "status": "processing",
            "tty": "/dev/ttys001",
            "tool": "Bash"
        }
        """
        let data = json.data(using: .utf8)!

        struct RawEvent: Decodable {
            let session_id: String
            let pid: Int
            let cwd: String
            let status: String
            let tty: String?
            let tool: String?
        }

        let raw = try JSONDecoder().decode(RawEvent.self, from: data)
        #expect(raw.session_id == "abc-123")
        #expect(raw.pid == 42)
        #expect(raw.cwd == "/Users/test/project")
        #expect(raw.status == "processing")
        #expect(raw.tty == "/dev/ttys001")
        #expect(raw.tool == "Bash")
    }

    @Test("Event with missing optional fields parses correctly")
    func missingOptionalFieldsParse() throws {
        let json = """
        {
            "session_id": "abc-123",
            "pid": 42,
            "cwd": "/tmp",
            "status": "waiting_for_input"
        }
        """
        let data = json.data(using: .utf8)!

        struct RawEvent: Decodable {
            let session_id: String
            let pid: Int
            let cwd: String
            let status: String
            let tty: String?
            let tool: String?
        }

        let raw = try JSONDecoder().decode(RawEvent.self, from: data)
        #expect(raw.tty == nil)
        #expect(raw.tool == nil)
    }

    @Test("Malformed JSON fails to parse")
    func malformedJsonFails() {
        let data = "not json".data(using: .utf8)!

        struct RawEvent: Decodable {
            let session_id: String
            let pid: Int
            let cwd: String
            let status: String
        }

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RawEvent.self, from: data)
        }
    }

    @Test("Missing required field fails to parse")
    func missingRequiredFieldFails() {
        let json = """
        {
            "session_id": "abc",
            "cwd": "/tmp",
            "status": "processing"
        }
        """
        let data = json.data(using: .utf8)!

        struct RawEvent: Decodable {
            let session_id: String
            let pid: Int
            let cwd: String
            let status: String
        }

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RawEvent.self, from: data)
        }
    }

    // MARK: - Status Mapping Completeness

    @Test("All hook event statuses have a mapping")
    @MainActor
    func allStatusesMapped() {
        let manager = InstanceManager(skipBootstrap: true)
        let statuses = [
            "processing", "running_tool", "compacting",
            "waiting_for_input", "waiting_for_approval",
            "ended", "unknown", "notification"
        ]

        for (index, status) in statuses.enumerated() {
            manager.handleSocketEvent(.init(
                sessionId: "s-\(index)", pid: 100 + index,
                cwd: "/tmp", status: status, tty: nil, tool: nil
            ))
        }

        // "ended" should have been removed
        #expect(manager.instances["s-5"] == nil)
        // All others should exist
        #expect(manager.instances.count == statuses.count - 1)
    }
}
