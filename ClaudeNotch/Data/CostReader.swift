import Foundation

struct CostInfo {
    let totalCost: Double
    let model: String?
    let contextPercent: Double?
}

/// Reads cost tracker JSON files written by Claude Code.
/// Files live at ~/.claude-work/cost-tracker/sessions/{pid}-{date}.json
/// or ~/.claude/cost-tracker/sessions/{pid}-{date}.json (personal accounts).
struct CostReader {
    private static let defaultContextWindow: Double = 200_000.0

    private static func contextWindow(fromModel model: String?) -> Double {
        guard let model = model?.lowercased(),
              let openParen = model.lastIndex(of: "("),
              let closeParen = model.lastIndex(of: ")"),
              openParen < closeParen else {
            return defaultContextWindow
        }
        let inner = String(model[model.index(after: openParen)..<closeParen])
            .trimmingCharacters(in: .whitespaces)
        guard inner.hasSuffix("context") else { return defaultContextWindow }
        let sizeStr = inner.dropLast("context".count)
            .trimmingCharacters(in: .whitespaces)
        let value: Double
        if sizeStr.hasSuffix("m"), let num = Double(sizeStr.dropLast()) {
            value = num * 1_000_000
        } else if sizeStr.hasSuffix("k"), let num = Double(sizeStr.dropLast()) {
            value = num * 1_000
        } else {
            return defaultContextWindow
        }
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

        guard let best = bestFile, let data = fm.contents(atPath: best.path) else {
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
            guard let cacheRead = file.last_tokens?.cache_read else { return nil }
            let window: Double
            if let explicit = file.context_window, explicit > 0 {
                window = Double(explicit)
            } else {
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
