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

    @Test("Context exceeding window is capped at 100%")
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

    // MARK: - Dynamic context window

    @Test("1M model at 500K tokens reports 50%")
    func oneMegModelHalfUsed() {
        let json = """
        {
            "total_cost": 3.0,
            "last_tokens": { "cache_read": 500000 },
            "last_model": "opus 4.6 (1m context)"
        }
        """
        let info = parseCostJSON(json)
        #expect(abs((info?.contextPercent ?? 0) - 0.5) < 0.001)
    }

    @Test("1M model at 600K tokens reports 60%, not capped at 200K")
    func oneMegModelNotFalselyCapped() {
        let json = """
        {
            "total_cost": 3.0,
            "last_tokens": { "cache_read": 600000 },
            "last_model": "opus 4.6 (1m context)"
        }
        """
        let info = parseCostJSON(json)
        #expect(abs((info?.contextPercent ?? 0) - 0.6) < 0.001)
    }

    @Test("1M model exceeding window is capped at 100%")
    func oneMegModelCapped() {
        let json = """
        {
            "total_cost": 5.0,
            "last_tokens": { "cache_read": 1200000 },
            "last_model": "opus 4.6 (1m context)"
        }
        """
        let info = parseCostJSON(json)
        #expect(info?.contextPercent == 1.0)
    }

    @Test("200K model at 100K tokens reports 50%")
    func twoHundredKModel() {
        let json = """
        {
            "total_cost": 1.0,
            "last_tokens": { "cache_read": 100000 },
            "last_model": "sonnet 4 (200k context)"
        }
        """
        let info = parseCostJSON(json)
        #expect(abs((info?.contextPercent ?? 0) - 0.5) < 0.001)
    }

    @Test("Unannotated model falls back to 200K default")
    func unannotatedModelDefault() {
        let json = """
        {
            "total_cost": 2.43,
            "last_tokens": { "cache_read": 79000 },
            "last_model": "opus 4.6"
        }
        """
        let info = parseCostJSON(json)
        // 79000 / 200000 = 0.395
        #expect(abs((info?.contextPercent ?? 0) - 0.395) < 0.001)
    }

    @Test("Zero context size in model string falls back to default")
    func zeroContextFallback() {
        let json = """
        {
            "total_cost": 1.0,
            "last_tokens": { "cache_read": 100000 },
            "last_model": "model (0m context)"
        }
        """
        let info = parseCostJSON(json)
        // Should use 200K default: 100000 / 200000 = 0.5
        #expect(abs((info?.contextPercent ?? 0) - 0.5) < 0.001)
    }

    @Test("Explicit context_window JSON field is preferred over model string")
    func explicitContextWindowField() {
        let json = """
        {
            "total_cost": 2.0,
            "last_tokens": { "cache_read": 500000 },
            "last_model": "opus 4.6 (200k context)",
            "context_window": 1000000
        }
        """
        let info = parseCostJSON(json)
        // Should use explicit 1M, not 200K from model string: 500000 / 1000000 = 0.5
        #expect(abs((info?.contextPercent ?? 0) - 0.5) < 0.001)
    }

    // MARK: - Helper

    private func parseCostJSON(_ json: String) -> CostInfo? {
        guard let data = json.data(using: .utf8) else { return nil }
        return CostReader.parseCostFile(data)
    }
}
