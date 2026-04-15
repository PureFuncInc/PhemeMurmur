import Foundation

enum MetricsLogger {
    private static let lock = NSLock()

    static var providerTimingLogPath: String {
        let configDir = (Config.configPath as NSString).deletingLastPathComponent
        return (configDir as NSString).appendingPathComponent("provider-timing.log")
    }

    static func appendProviderTiming(
        provider: String,
        model: String,
        operation: String,
        audioBytes: Int,
        elapsedMs: Int,
        status: String,
        httpStatus: Int? = nil,
        error: String? = nil
    ) {
        guard Config.providerTimingLogEnabled else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var fields = [
            "ts=\(formatter.string(from: Date()))",
            "provider=\(sanitize(provider))",
            "model=\(sanitize(model))",
            "operation=\(sanitize(operation))",
            "audio_bytes=\(audioBytes)",
            "elapsed_ms=\(elapsedMs)",
            "status=\(sanitize(status))",
        ]

        if let httpStatus {
            fields.append("http_status=\(httpStatus)")
        }

        if let error, !error.isEmpty {
            fields.append("error=\(sanitize(error))")
        }

        let line = fields.joined(separator: " ") + "\n"

        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        let logPath = providerTimingLogPath
        let dir = (logPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: logPath) {
            try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
        } else if let handle = FileHandle(forWritingAtPath: logPath) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(Data(line.utf8))
        }

        print("Provider timing: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "_")
    }
}
