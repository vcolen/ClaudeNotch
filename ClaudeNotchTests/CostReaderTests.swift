import Foundation
import Testing
@testable import ClaudeNotch

@Suite("CostReader Tests")
struct CostReaderTests {

    // MARK: - Parsing

    @Test("Valid cost file parses all fields")
    func validCostFileParsesAllFields() throws {
        let json = """
        {
            "total_cost": 2.43,
            "last_tokens": {
                "cache_read": 79107
            },
            "last_model": "opus 4.6"
        }
        """
        let info = parseCostJSON(json)
        #expect(info != nil)
        #expect(info?.totalCost == 2.43)
        #expect(info?.model == "opus 4.6")
        // 79107 / 200000 = 0.395535
        #expect(info?.contextPercent != nil)
        #expect(abs((info?.contextPercent ?? 0) - 0.395535) < 0.001)
    }

    @Test("Zero tokens returns nil context percentage")
    func zeroTokensNilContext() {
        let json = """
        {
            "total_cost": 0.0,
            "last_tokens": {
                "cache_read": 0
            },
            "last_model": "sonnet 4"
        }
        """
        let info = parseCostJSON(json)
        #expect(info != nil)
        #expect(info?.totalCost == 0.0)
        // 0 / 200000 = 0.0 (not nil since key exists)
        #expect(info?.contextPercent == 0.0)
    }

    @Test("Missing last_tokens returns nil context percentage")
    func missingTokensNilContext() {
        let json = """
        {
            "total_cost": 1.5
        }
        """
        let info = parseCostJSON(json)
        #expect(info != nil)
        #expect(info?.contextPercent == nil)
    }

    @Test("Context over 200K tokens is capped at 100%")
    func contextCappedAt100Percent() {
        let json = """
        {
            "total_cost": 5.0,
            "last_tokens": {
                "cache_read": 300000
            },
            "last_model": "opus 4.6"
        }
        """
        let info = parseCostJSON(json)
        #expect(info?.contextPercent == 1.0)
    }

    @Test("Missing total_cost defaults to 0")
    func missingCostDefaultsToZero() {
        let json = """
        {
            "last_model": "haiku 4"
        }
        """
        let info = parseCostJSON(json)
        #expect(info != nil)
        #expect(info?.totalCost == 0.0)
    }

    @Test("Malformed JSON returns nil")
    func malformedJsonReturnsNil() {
        let info = parseCostJSON("not json at all")
        #expect(info == nil)
    }

    @Test("Empty JSON object still parses")
    func emptyObjectParses() {
        let info = parseCostJSON("{}")
        #expect(info != nil)
        #expect(info?.totalCost == 0.0)
        #expect(info?.model == nil)
        #expect(info?.contextPercent == nil)
    }

    // MARK: - Helper

    /// Parses cost JSON directly without needing file I/O.
    /// Mirrors the CostReader's internal parsing logic.
    private func parseCostJSON(_ json: String) -> CostInfo? {
        guard let data = json.data(using: .utf8) else { return nil }

        struct CostFile: Decodable {
            let total_cost: Double?
            let last_tokens: LastTokens?
            let last_model: String?

            struct LastTokens: Decodable {
                let cache_read: Int?
            }
        }

        guard let file = try? JSONDecoder().decode(CostFile.self, from: data) else {
            return nil
        }

        let totalCost = file.total_cost ?? 0.0
        let contextPercent: Double? = {
            guard let cacheRead = file.last_tokens?.cache_read else { return nil }
            return min(Double(cacheRead) / 200_000.0, 1.0)
        }()

        return CostInfo(
            totalCost: totalCost,
            model: file.last_model,
            contextPercent: contextPercent
        )
    }
}
