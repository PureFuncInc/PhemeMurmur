import Foundation

struct PromptTemplate: Decodable {
    let language: String?
    let prompt: String?
}

enum ProviderType: String, Decodable {
    case openai
    case gemini
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
    /// RMS energy threshold (0.0–1.0) below which a recording is considered silent; configurable via "silence-threshold"
    static var silenceThreshold: Double = 0.005
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

    // Hotkey to start/stop recording. Options: right-shift (default), right-option, right-control, right-command, fn
    // "hotkey": "right-shift",

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
    }
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

    /// Writes (or updates) the "hotkey" field in config.jsonc, preserving all other content.
    static func saveHotkey(_ key: HotkeyKey) {
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }
        let newEntry = "\"hotkey\": \"\(key.rawValue)\""

        // Replace existing hotkey field if present
        if let range = content.range(of: #""hotkey"\s*:\s*"[^"]*""#, options: .regularExpression) {
            content.replaceSubrange(range, with: newEntry)
        } else if let idx = content.firstIndex(of: "{") {
            // Insert as first field after the opening brace
            content.insert(contentsOf: "\n    \(newEntry),", at: content.index(after: idx))
        }

        try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
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
