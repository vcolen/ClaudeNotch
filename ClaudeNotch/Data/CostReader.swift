import Foundation

struct CostInfo {
    let totalCost: Double
    let model: String?
    let contextPercent: Double?
}

/// Reads cost tracker JSON files written by Claude Code.
/// Files live at ~/.claude-work/cost-tracker/sessions/{pid}-{date}.json
struct CostReader {
    private static let contextWindow: Double = 200_000.0
    private let sessionsDir: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sessionsDir = "\(home)/.claude-work/cost-tracker/sessions"
    }

    /// Read the most recent cost file for the given PID.
    /// Returns nil if no matching file is found or the file cannot be parsed.
    func readCost(forPID pid: Int) -> CostInfo? {
        let fm = FileManager.default
        let prefix = "\(pid)-"

        guard let entries = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
            return nil
        }

        // Find all files matching this PID, sort by name descending
        // (filenames contain dates, so lexicographic sort gives most recent last)
        let matching = entries
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
            .sorted()

        guard let mostRecent = matching.last else {
            return nil
        }

        let filePath = (sessionsDir as NSString).appendingPathComponent(mostRecent)
        guard let data = fm.contents(atPath: filePath) else {
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
        guard let file = try? JSONDecoder().decode(CostFile.self, from: data) else {
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
