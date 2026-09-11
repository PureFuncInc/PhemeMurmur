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

    /// The most recent entries, reformatted for the diagnostics console: the
    /// stored `ts=… context=… message=…` lines are dense machine records, so
    /// each is re-laid-out as `MM-DD HH:MM:SS  context  message`.
    ///
    /// Returns a placeholder rather than an empty string so the panel never
    /// collapses to a bare outline when nothing has gone wrong yet.
    static func tail(lines limit: Int = 4) -> String {
        lock.lock()
        defer { lock.unlock() }

        guard let raw = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return "— 沒有錯誤記錄 —"
        }
        let entries = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)
            .map { formatForDisplay(String($0)) }

        return entries.isEmpty ? "— 沒有錯誤記錄 —" : entries.joined(separator: "\n")
    }

    private static func formatForDisplay(_ line: String) -> String {
        let (rawContext, message) = parseFields(line)
        let stamp = parseTimestamp(from: line).map { date -> String in
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm:ss"
            return f.string(from: date)
        } ?? "---- --:--:--"
        let context = rawContext.isEmpty ? "?" : rawContext
        // Pad the context so the messages line up into a column.
        let paddedContext = context.padding(toLength: max(context.count, 16),
                                            withPad: " ", startingAt: 0)
        return "\(stamp)  \(paddedContext)  \(message)"
    }

    /// Splits a log line into its context and message.
    ///
    /// `append` writes `ts=… context=… message=…` and `sanitize` only strips
    /// newlines and tabs — it does not quote or escape spaces. So the message is
    /// whatever follows `message=` to the end of the line, and a generic
    /// space-delimited parse would truncate it at the first word.
    private static func parseFields(_ line: String) -> (context: String, message: String) {
        let contextMarker = " context="
        let messageMarker = " message="

        var context = ""
        var message = ""

        if let messageRange = line.range(of: messageMarker) {
            message = String(line[messageRange.upperBound...])
            if let contextRange = line.range(of: contextMarker),
               contextRange.upperBound <= messageRange.lowerBound {
                context = String(line[contextRange.upperBound..<messageRange.lowerBound])
            }
        } else if let contextRange = line.range(of: contextMarker) {
            // A truncated line still has a usable context.
            context = String(line[contextRange.upperBound...])
        }

        return (context.trimmingCharacters(in: .whitespaces),
                message.trimmingCharacters(in: .whitespaces))
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
