import Foundation

public struct PromptTemplate: Decodable, Sendable {
    public let language: String?
    public let prompt: String?
}

public enum ProviderType: String, Decodable {
    case openai
    case apple
}

extension ProviderType {
    /// Hard-coded ordered list of model names to try for this provider.
    /// Intended for automatic fallback when the primary model returns HTTP 429.
    public var fallbackChain: [String] {
        switch self {
        case .openai:
            return [OpenAIProvider.defaultModel]
        case .apple:
            return ["apple-speech-on-device"]
        }
    }
}

public struct PostProcessConfig: Decodable {
    public let baseURL: String?
    public let model: String?

    enum CodingKeys: String, CodingKey {
        case baseURL = "base-url"
        case model
    }
}

public struct ProviderEntry: Decodable {
    public let type: ProviderType
    public let apiKey: String?
    public let postProcess: PostProcessConfig?

    enum CodingKeys: String, CodingKey {
        case type
        case apiKey = "api-key"
        case postProcess = "post-process"
    }
}

public struct ConfigFile: Decodable {
    public let providers: [String: ProviderEntry]?
    public let activeProvider: String?
    public let prefix: String?
    public let promptTemplates: [String: PromptTemplate]?
    public let activePromptTemplate: String?
    public let hotkey: String?
    public let silenceThreshold: Double?
    public let voiceCommands: Bool?

    enum CodingKeys: String, CodingKey {
        case providers
        case activeProvider = "active-provider"
        case prefix
        case promptTemplates = "prompt-templates"
        case activePromptTemplate = "active-prompt-template"
        case hotkey
        case silenceThreshold = "silence-threshold"
        case voiceCommands = "voice-commands"
    }

    public var resolvedHotkey: String {
        hotkey ?? "right-shift"
    }

    /// Builds the full provider map from the `providers` dict.
    public var resolvedProviders: [String: ProviderEntry] {
        providers ?? [:]
    }

    /// Resolves the default active provider name.
    public var resolvedActiveProvider: String? {
        if let activeProvider { return activeProvider }
        let resolved = resolvedProviders
        if resolved.count == 1 { return resolved.keys.first }
        // Default to first sorted key
        return resolved.keys.sorted().first
    }

    /// Defaults to false: feature must be explicitly opted into.
    public var resolvedVoiceCommands: Bool {
        voiceCommands ?? false
    }
}

public enum Config {
    public static let sampleRate: Double = 16000
    public static let channels: UInt32 = 1
    public static let minDuration: Double = 0.5
    public nonisolated(unsafe) static var silenceThreshold: Double = 0
    public static let debounceInterval: Double = 0.4

    public static let defaultPromptTemplateName = "zh_TW"

    public static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/pheme-murmur/config.json"
    }()

    static let defaultConfigContent = """
{
    "providers": {
        "Apple": { "type": "apple" },
        "OpenAI": { "type": "openai", "api-key": "sk-proj-xxx" }
    },
    "active-provider": "Apple",
    "hotkey": "right-shift",
    "prefix": "",
    "silence-threshold": 0,
    "prompt-templates": {
        "zh_TW": { "language": "zh" },
        "zh_TW-en_US": { "language": "zh", "prompt": "Translate the following text to English. Output ONLY the English translation, nothing else." }
    },
    "active-prompt-template": "zh_TW",
    "voice-commands": false
}
"""

    /// Creates the config directory and a default config.json if neither exists yet.
    public static func createDefaultConfigIfNeeded() {
        let fm = FileManager.default
        let dir = (configPath as NSString).deletingLastPathComponent
        guard !fm.fileExists(atPath: configPath) else { return }
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? defaultConfigContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        print("Created default config at \(configPath)")
        print("Edit it and add your provider API keys to get started.")
    }

    /// Writes (or updates) the api-key for a provider in config.json, preserving all other content.
    /// Looks for the provider inside the `providers` dict.
    /// Returns true if the file was updated.
    @discardableResult
    public static func saveAPIKey(providerName: String, apiKey: String) -> Bool {
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return false }

        // JSON-escape the new key so quotes/backslashes don't break the file.
        let jsonEscaped = apiKey
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Also escape $ and \ for the NSRegularExpression replacement template.
        let templateKey = NSRegularExpression.escapedTemplate(for: jsonEscaped)

        func replace(pattern: String, in source: inout String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                return false
            }
            let range = NSRange(source.startIndex..., in: source)
            guard regex.firstMatch(in: source, options: [], range: range) != nil else { return false }
            source = regex.stringByReplacingMatches(
                in: source,
                options: [],
                range: range,
                withTemplate: "$1\(templateKey)$2"
            )
            return true
        }

        // Try modern `providers` dict first.
        let escapedName = NSRegularExpression.escapedPattern(for: providerName)
        let providersPattern = "(\"\(escapedName)\"\\s*:\\s*\\{[^}]*?\"api-key\"\\s*:\\s*\")[^\"]*(\")"
        if replace(pattern: providersPattern, in: &content) {
            try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
            return true
        }

        return false
    }

    /// Writes (or updates) a top-level string field in config.json, preserving all other content.
    /// Assumes the field already exists — the default config template
    /// writes all user-adjustable fields as real entries so this simple regex is sufficient.
    private static func saveTopLevelStringField(_ fieldName: String, value: String) {
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }

        let jsonEscapedValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let newEntry = "\"\(fieldName)\": \"\(jsonEscapedValue)\""

        let escapedName = NSRegularExpression.escapedPattern(for: fieldName)
        let pattern = "\"\(escapedName)\"\\s*:\\s*\"[^\"]*\""
        if let range = content.range(of: pattern, options: .regularExpression) {
            content.replaceSubrange(range, with: newEntry)
        } else if let idx = content.firstIndex(of: "{") {
            content.insert(contentsOf: "\n    \(newEntry),", at: content.index(after: idx))
        }

        try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Writes (or updates) the "hotkey" field in config.json, preserving all other content.
    public static func saveHotkey(_ rawValue: String) {
        saveTopLevelStringField("hotkey", value: rawValue)
    }

    /// Writes (or updates) the "active-provider" field in config.json.
    public static func saveActiveProvider(_ name: String) {
        saveTopLevelStringField("active-provider", value: name)
    }

    /// Writes (or updates) the "active-prompt-template" field in config.json.
    public static func saveActivePromptTemplate(_ name: String) {
        saveTopLevelStringField("active-prompt-template", value: name)
    }

    public static func loadConfig() -> ConfigFile? {
        guard let data = FileManager.default.contents(atPath: configPath) else { return nil }
        return try? JSONDecoder().decode(ConfigFile.self, from: data)
    }
}
