import Foundation

struct PromptTemplate: Decodable {
    let language: String?
    let prompt: String?
}

enum ProviderType: String, Decodable {
    case openai
    case gemini
}

extension ProviderType {
    /// Hard-coded ordered list of model names to try for this provider.
    /// Intended for automatic fallback when the primary model returns HTTP 429.
    var fallbackChain: [String] {
        switch self {
        case .gemini:
            return [
                GeminiProvider.defaultModel,
                "gemini-2.5-flash",
                "gemini-2.0-flash-lite",
            ]
        case .openai:
            return [OpenAIProvider.defaultModel]
        }
    }
}

struct ProviderEntry: Decodable {
    let type: ProviderType
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case type
        case apiKey = "api-key"
    }
}

struct ConfigFile: Decodable {
    // Legacy single-key fields
    let openaiApiKey: String?
    let geminiApiKey: String?
    let provider: ProviderType?

    // Multi-provider support
    let providers: [String: ProviderEntry]?
    let activeProvider: String?

    let prefix: String?
    let promptTemplates: [String: PromptTemplate]?
    let activePromptTemplate: String?
    let hotkey: String?
    let silenceThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case openaiApiKey = "openai-api-key"
        case geminiApiKey = "gemini-api-key"
        case provider
        case providers
        case activeProvider = "active-provider"
        case prefix
        case promptTemplates = "prompt-templates"
        case activePromptTemplate = "active-prompt-template"
        case hotkey
        case silenceThreshold = "silence-threshold"
    }

    var resolvedHotkey: HotkeyKey {
        guard let raw = hotkey, let k = HotkeyKey(rawValue: raw) else { return .rightShift }
        return k
    }

    /// Builds the full provider map — from `providers` dict, or falling back to legacy single-key fields.
    var resolvedProviders: [String: ProviderEntry] {
        if let providers, !providers.isEmpty { return providers }
        // Fallback: build from legacy single-key fields
        var result: [String: ProviderEntry] = [:]
        if let key = openaiApiKey {
            result["openai"] = ProviderEntry(type: .openai, apiKey: key)
        }
        if let key = geminiApiKey {
            result["gemini"] = ProviderEntry(type: .gemini, apiKey: key)
        }
        return result
    }

    /// Resolves the default active provider name.
    var resolvedActiveProvider: String? {
        if let activeProvider { return activeProvider }
        // Legacy: use explicit provider field
        if let provider { return provider.rawValue }
        let resolved = resolvedProviders
        if resolved.count == 1 { return resolved.keys.first }
        // Default to first sorted key
        return resolved.keys.sorted().first
    }
}

enum Config {
    /// Audio sample rate in Hz (16 kHz, required by Whisper)
    static let sampleRate: Double = 16000
    /// Number of audio channels (mono)
    static let channels: UInt32 = 1
    /// Minimum recording duration in seconds; shorter recordings are discarded
    static let minDuration: Double = 0.5
    /// RMS energy threshold (0.0–1.0) below which a recording is considered silent; configurable via "silence-threshold".
    /// Set to 0 to disable silence detection entirely.
    static var silenceThreshold: Double = 0.0005
    /// Minimum interval in seconds between hotkey toggles to prevent accidental double-taps
    static let debounceInterval: Double = 0.4

    static let defaultPromptTemplateName = "zh_TW"

    static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/pheme-murmur/config.jsonc"
    }()

    static let defaultConfigContent = """
{
    "providers": {
        "OpenAI": { "type": "openai", "api-key": "sk-proj-xxx" },
        "Gemini": { "type": "gemini", "api-key": "..." }
    },
    "active-provider": "OpenAI",

    // Hotkey to start/stop recording. Options: right-shift, right-option, right-control, right-command, fn
    "hotkey": "right-shift",

    // Optional: text to prepend before every transcription result
    // "prefix": "",

    // Optional: RMS energy threshold (0.0–1.0) for silence detection. Recordings below this are discarded (default: 0.005)
    // "silence-threshold": 0.005,

    // Prompt templates — switchable from the menu bar.
    //   "language": input audio language (ISO-639-1), helps transcription accuracy
    //   "prompt": if set, sends transcribed text through LLM for post-processing
    "prompt-templates": {
        "zh_TW": { "language": "zh" },
        "zh_TW-en_US": { "language": "zh", "prompt": "Translate the following text to English. Output ONLY the English translation, nothing else." }
    },
    "active-prompt-template": "zh_TW"
}
"""

    /// Creates the config directory and a default config.jsonc if neither exists yet.
    static func createDefaultConfigIfNeeded() {
        let fm = FileManager.default
        let dir = (configPath as NSString).deletingLastPathComponent
        guard !fm.fileExists(atPath: configPath) else { return }
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? defaultConfigContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        print("Created default config at \(configPath)")
        print("Edit it and add your OpenAI API key to get started.")
    }

    /// Writes (or updates) the api-key for a provider in config.jsonc, preserving all other content.
    /// Looks for the provider inside the `providers` dict; falls back to legacy single-key fields
    /// (`openai-api-key` / `gemini-api-key`) when the modern block is absent.
    /// Returns true if the file was updated.
    @discardableResult
    static func saveAPIKey(providerName: String, apiKey: String) -> Bool {
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

        // Fallback: legacy top-level single-key fields keyed by provider type.
        let legacyField: String?
        switch providerName.lowercased() {
        case "openai": legacyField = "openai-api-key"
        case "gemini": legacyField = "gemini-api-key"
        default: legacyField = nil
        }
        if let legacyField {
            let legacyPattern = "(\"\(legacyField)\"\\s*:\\s*\")[^\"]*(\")"
            if replace(pattern: legacyPattern, in: &content) {
                try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
                return true
            }
        }

        return false
    }

    /// Writes (or updates) a top-level string field in config.jsonc, preserving all other content.
    /// Assumes the field exists as a real (uncommented) entry — the default config template
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

    /// Writes (or updates) the "hotkey" field in config.jsonc, preserving all other content.
    static func saveHotkey(_ key: HotkeyKey) {
        saveTopLevelStringField("hotkey", value: key.rawValue)
    }

    /// Writes (or updates) the "active-provider" field in config.jsonc.
    static func saveActiveProvider(_ name: String) {
        saveTopLevelStringField("active-provider", value: name)
    }

    /// Writes (or updates) the "active-prompt-template" field in config.jsonc.
    static func saveActivePromptTemplate(_ name: String) {
        saveTopLevelStringField("active-prompt-template", value: name)
    }

    static func loadConfig() -> ConfigFile? {
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        let stripped = stripComments(from: json)
        guard let strippedData = stripped.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ConfigFile.self, from: strippedData)
    }

    // Strips // line comments and /* */ block comments, respecting string literals.
    private static func stripComments(from source: String) -> String {
        var result = ""
        var i = source.startIndex
        var inString = false

        while i < source.endIndex {
            let c = source[i]
            let next = source.index(after: i)

            if inString {
                result.append(c)
                if c == "\\" && next < source.endIndex {
                    // Escaped character — keep both chars, skip ahead
                    result.append(source[next])
                    i = source.index(after: next)
                } else {
                    if c == "\"" { inString = false }
                    i = next
                }
            } else {
                if c == "\"" {
                    inString = true
                    result.append(c)
                    i = next
                } else if c == "/" && next < source.endIndex {
                    let n = source[next]
                    if n == "/" {
                        // Line comment — skip to end of line
                        var j = source.index(after: next)
                        while j < source.endIndex && source[j] != "\n" { j = source.index(after: j) }
                        i = j
                    } else if n == "*" {
                        // Block comment — skip to */
                        var j = source.index(after: next)
                        while j < source.endIndex {
                            let jNext = source.index(after: j)
                            if source[j] == "*" && jNext < source.endIndex && source[jNext] == "/" {
                                i = source.index(after: jNext)
                                break
                            }
                            j = source.index(after: j)
                        }
                    } else {
                        result.append(c)
                        i = next
                    }
                } else {
                    result.append(c)
                    i = next
                }
            }
        }
        return result
    }
}
