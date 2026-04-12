import Foundation

struct ConfigFile: Decodable {
    let apiKey: String
    let prefix: String?

    enum CodingKeys: String, CodingKey {
        case apiKey = "openai-api-key"
        case prefix
    }
}

enum Config {
    static let sampleRate: Double = 16000
    static let channels: UInt32 = 1
    static let minDuration: Double = 0.5
    static let debounceInterval: Double = 0.4

    static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/pheme-murmur/config.json"
    }()

    static func loadConfig() -> ConfigFile? {
        guard let data = FileManager.default.contents(atPath: configPath) else {
            return nil
        }
        return try? JSONDecoder().decode(ConfigFile.self, from: data)
    }
}
