import Foundation

enum ErrorLog {
    private static let lock = NSLock()
    private static let retentionDays = 7
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var logPath: String {
        let configDir = (Config.configPath as NSString).deletingLastPathComponent
        return (configDir as NSString).appendingPathComponent("error.log")
    }

    static func append(context: String, message: String) {
        let now = Date()
        let line = "ts=\(formatter.string(from: now)) context=\(sanitize(context)) message=\(sanitize(message))\n"

        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        let path = logPath
        let dir = (path as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 3600)
        let kept = prunedLines(atPath: path, cutoff: cutoff)
        let output = kept.joined() + line
        try? output.write(toFile: path, atomically: true, encoding: .utf8)

        print("Error logged: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private static func prunedLines(atPath path: String, cutoff: Date) -> [String] {
        guard let existing = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        var kept: [String] = []
        for raw in existing.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }) {
            if raw.isEmpty { continue }
            guard let ts = parseTimestamp(from: String(raw)), ts >= cutoff else { continue }
            kept.append(String(raw) + "\n")
        }
        return kept
    }

    private static func parseTimestamp(from line: String) -> Date? {
        guard line.hasPrefix("ts=") else { return nil }
        let rest = line.dropFirst(3)
        guard let space = rest.firstIndex(of: " ") else { return nil }
        return formatter.date(from: String(rest[..<space]))
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }
}
