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
    private static let contextWindow: Double = 200_000.0
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

        return parseCostFile(data)
    }

    // MARK: - Parsing

    private struct CostFile: Decodable {
        let total_cost: Double?
        let last_tokens: LastTokens?
        let last_model: String?

        struct LastTokens: Decodable {
            let cache_read: Int?
        }
    }

    private func parseCostFile(_ data: Data) -> CostInfo? {
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
            return min(Double(cacheRead) / Self.contextWindow, 1.0)
        }()

        return CostInfo(
            totalCost: totalCost,
            model: file.last_model,
            contextPercent: contextPercent
        )
    }
}
