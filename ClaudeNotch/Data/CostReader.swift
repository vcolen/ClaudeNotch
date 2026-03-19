import Foundation

struct CostInfo {
    let totalCost: Double
    let model: String?
    let contextPercent: Double?
}

/// Reads cost tracker JSON files written by Claude Code.
/// Files live at ~/.claude-work/cost-tracker/sessions/{pid}-{date}.json
/// or ~/.claude/cost-tracker/sessions/{pid}-{date}.json (personal accounts).
///
/// Context window size is determined by (in priority order):
/// 1. An explicit `context_window` field in the JSON
/// 2. A parenthesized annotation in the model string, e.g. "(1m context)"
/// 3. A 200K token default
struct CostReader {
    private static let defaultContextWindow: Double = 200_000.0

    /// Extracts context window size from a model string like "opus 4.6 (1m context)".
    /// Supports "k" (thousands) and "m" (millions) suffixes.
    /// Returns ``defaultContextWindow`` if the string is nil, unparseable, or yields a non-positive value.
    private static func contextWindow(fromModel model: String?) -> Double {
        guard let model else { return defaultContextWindow }
        guard let match = model.firstMatch(
            of: /\((\d+(?:\.\d+)?)\s*(m|k)\s+context\)/.ignoresCase()
        ) else {
            if model.contains("(") && model.contains(")") {
                NSLog("CostReader: model '%@' has parenthesized content but could not parse context window, using default", model)
            }
            return defaultContextWindow
        }
        guard let num = Double(match.1) else { return defaultContextWindow }
        let multiplier: Double = match.2.lowercased() == "m" ? 1_000_000 : 1_000
        let value = num * multiplier
        return value > 0 ? value : defaultContextWindow
    }

    private let sessionsDirs: [String]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sessionsDirs = [
            "\(home)/.claude-work/cost-tracker/sessions",
            "\(home)/.claude/cost-tracker/sessions",
        ]
    }

    /// Read the most recent cost file for the given PID.
    /// Returns nil if no matching file is found or the file cannot be parsed.
    func readCost(forPID pid: Int) -> CostInfo? {
        let fm = FileManager.default
        let prefix = "\(pid)-"

        var bestFile: (path: String, name: String)?

        for dir in sessionsDirs {
            let entries: [String]
            do {
                entries = try fm.contentsOfDirectory(atPath: dir)
            } catch {
                if fm.fileExists(atPath: dir) {
                    NSLog("CostReader: cannot read sessions dir %@: %@", dir, "\(error)")
                }
                continue
            }

            let matching = entries
                .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
                .sorted()

            if let last = matching.last {
                if bestFile == nil || last > bestFile!.name {
                    bestFile = (path: (dir as NSString).appendingPathComponent(last), name: last)
                }
            }
        }

        guard let best = bestFile else { return nil }
        guard let data = fm.contents(atPath: best.path) else {
            NSLog("CostReader: found cost file at %@ but could not read its contents", best.path)
            return nil
        }

        return Self.parseCostFile(data)
    }

    // MARK: - Parsing

    private struct CostFile: Decodable {
        let total_cost: Double?
        let last_tokens: LastTokens?
        let last_model: String?
        let context_window: Int?

        struct LastTokens: Decodable {
            let cache_read: Int?
        }
    }

    static func parseCostFile(_ data: Data) -> CostInfo? {
        let file: CostFile
        do {
            file = try JSONDecoder().decode(CostFile.self, from: data)
        } catch {
            NSLog("CostReader: failed to parse cost file: %@", "\(error)")
            return nil
        }

        let totalCost = file.total_cost ?? 0.0

        let contextPercent: Double? = {
            guard let cacheRead = file.last_tokens?.cache_read, cacheRead >= 0 else { return nil }
            let window: Double
            if let explicit = file.context_window, explicit > 0, explicit <= 10_000_000 {
                window = Double(explicit)
            } else {
                if let explicit = file.context_window {
                    NSLog("CostReader: context_window %d is out of expected range (0, 10M], falling back to model string", explicit)
                }
                window = Self.contextWindow(fromModel: file.last_model)
            }
            return min(Double(cacheRead) / window, 1.0)
        }()

        return CostInfo(
            totalCost: totalCost,
            model: file.last_model,
            contextPercent: contextPercent
        )
    }
}
