import Foundation

enum Config {
    static let sampleRate: Double = 16000
    static let channels: UInt32 = 1
    static let minDuration: Double = 0.5
    static let debounceInterval: Double = 0.4

    static let apiKeyPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/phememurmur/api_key"
    }()

    static func loadAPIKey() -> String? {
        guard let raw = try? String(contentsOfFile: apiKeyPath, encoding: .utf8) else {
            return nil
        }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}
