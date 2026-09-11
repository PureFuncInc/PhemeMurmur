import Foundation

struct PromptTemplate: Decodable {
    let language: String?
    let prompt: String?
}

enum ProviderType: String, Decodable {
    case openai
    case gemini
    case apple
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
                "gemini-2.5-flash-lite",
            ]
        case .openai:
            return [OpenAIProvider.defaultModel]
        case .apple:
            return ["apple-speech-on-device"]
        }
    }
}

struct PostProcessConfig: Decodable {
    let baseURL: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case baseURL = "base-url"
        case model
    }
}

struct ProviderEntry: Decodable {
    let type: ProviderType
    let apiKey: String?
    let postProcess: PostProcessConfig?

    enum CodingKeys: String, CodingKey {
        case type
        case apiKey = "api-key"
        case postProcess = "post-process"
    }
}

struct ConfigFile: Decodable {
    let providers: [String: ProviderEntry]?
    let activeProvider: String?
    let prefix: String?
    let promptTemplates: [String: PromptTemplate]?
    let activePromptTemplate: String?
    let hotkey: String?
    let silenceThreshold: Double?
    let voiceCommands: Bool?

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

    var resolvedHotkey: HotkeyKey {
        guard let raw = hotkey, let k = HotkeyKey(rawValue: raw) else { return .rightShift }
        return k
    }

    /// Builds the full provider map from the `providers` dict.
    var resolvedProviders: [String: ProviderEntry] {
        providers ?? [:]
    }

    /// Resolves the default active provider name.
    var resolvedActiveProvider: String? {
        if let activeProvider { return activeProvider }
        let resolved = resolvedProviders
        if resolved.count == 1 { return resolved.keys.first }
        // Default to first sorted key
        return resolved.keys.sorted().first
    }

    /// Defaults to false: feature must be explicitly opted into.
    var resolvedVoiceCommands: Bool {
        voiceCommands ?? false
    }
}

enum Config {
    /// Audio sample rate in Hz (16 kHz, required by Whisper)
    static let sampleRate: Double = 16000
    /// Number of audio channels (mono)
    static let channels: UInt32 = 1
    /// Minimum recording duration in seconds; shorter recordings are discarded
    static let minDuration: Double = 0.5
    /// RMS energy threshold (0.0–1.0) below which a recording is considered silent; configurable via "silence-threshold". Default is 0 (disabled). Set a positive value to enable, e.g.: 0.003
    static var silenceThreshold: Double = 0
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
        // Apple's on-device speech recognition (macOS 26+). No API key required.
        // First use downloads the language model and prompts for permission.
        "Apple": { "type": "apple" },
        "OpenAI": {
            "type": "openai",
            "api-key": "sk-proj-xxx"
            // Optional: route post-processing (chat completions) to an
            // OpenAI-compatible endpoint such as a local LM Studio server.
            // Defaults to OpenAI (https://api.openai.com/v1, gpt-5-nano).
            // "post-process": {
            //     "base-url": "http://localhost:1234/v1",
            //     "model": "openai/gpt-oss-20b"
            // }
        },
        "Gemini": { "type": "gemini", "api-key": "AIzaxxx" }
    },
    "active-provider": "Apple",

    // Hotkey to start/stop recording. Options: right-shift, right-option, right-control, right-command, fn
    "hotkey": "right-shift",

    // Optional: text to prepend before every transcription result
    // "prefix": "",

    // Optional: RMS energy threshold (0.0–1.0) for silence detection. Recordings below this are discarded. Default is 0 (disabled). Set a positive value to enable, e.g.: 0.003
    // "silence-threshold": 0.003,

    // Prompt templates — switchable from the menu bar.
    //   "language": input audio language (ISO-639-1), helps transcription accuracy
    //   "prompt": if set, sends transcribed text through LLM for post-processing
    "prompt-templates": {
        "zh_TW": { "language": "zh" },
        "zh_TW-en_US": { "language": "zh", "prompt": "Translate the following text to English. Output ONLY the English translation, nothing else." }
    },
    "active-prompt-template": "zh_TW",

    // Set to true to enable local voice-command post-processing. When on,
    // saying 換行 / 空行 / 分隔線 / 第一點…第十點 inserts the corresponding
    // formatting in the transcription before paste. Skipped when the
    // active prompt template has a "prompt" field.
    "voice-commands": false
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
        print("Edit it and add your provider API keys to get started.")
    }

    /// Writes (or updates) the api-key for a provider in config.jsonc, preserving all other content.
    /// Looks for the provider inside the `providers` dict.
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

        return false
    }

    /// Finds the first match of `pattern` that is not on a commented-out line (a line
    /// whose content, ignoring leading whitespace, starts with `//`). Several of the
    /// default config template's fields (e.g. "prefix", "silence-threshold") ship
    /// commented out; a naive whole-file regex would happily match inside the comment
    /// and "update" a value that stays commented out (and therefore never takes
    /// effect), silently failing to save. Scanning line-by-line avoids that.
    private static func firstUncommentedMatch(of pattern: String, in content: String) -> Range<String.Index>? {
        var searchStart = content.startIndex
        while searchStart < content.endIndex {
            let lineEnd = content[searchStart...].firstIndex(of: "\n") ?? content.endIndex
            let line = content[searchStart..<lineEnd]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                searchStart = lineEnd < content.endIndex ? content.index(after: lineEnd) : lineEnd
                continue
            }
            if let range = line.range(of: pattern, options: .regularExpression) {
                return range
            }
            searchStart = lineEnd < content.endIndex ? content.index(after: lineEnd) : lineEnd
        }
        return nil
    }

    /// Writes (or updates) a top-level string field in config.jsonc, preserving all other content.
    /// If the field only appears commented out (or not at all), a new real entry is inserted
    /// right after the opening `{` rather than uncommenting/corrupting the comment.
    private static func saveTopLevelStringField(_ fieldName: String, value: String) {
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }

        let jsonEscapedValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let newEntry = "\"\(fieldName)\": \"\(jsonEscapedValue)\""

        let escapedName = NSRegularExpression.escapedPattern(for: fieldName)
        let pattern = "\"\(escapedName)\"\\s*:\\s*\"[^\"]*\""
        if let range = firstUncommentedMatch(of: pattern, in: content) {
            content.replaceSubrange(range, with: newEntry)
        } else if let idx = content.firstIndex(of: "{") {
            content.insert(contentsOf: "\n    \(newEntry),", at: content.index(after: idx))
        }

        try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Writes (or updates) a top-level field whose value is not a JSON string
    /// (booleans, numbers). Same preserve-the-rest-of-the-file approach as
    /// saveTopLevelStringField, but without quoting the value, and skipping
    /// commented-out occurrences the same way.
    private static func saveTopLevelRawField(_ fieldName: String, rawValue: String) {
        guard var content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }

        let newEntry = "\"\(fieldName)\": \(rawValue)"
        let escapedName = NSRegularExpression.escapedPattern(for: fieldName)
        let pattern = "\"\(escapedName)\"\\s*:\\s*[^,\\n}]+"
        if let range = firstUncommentedMatch(of: pattern, in: content) {
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

    /// Writes (or updates) the "voice-commands" field in config.jsonc.
    static func saveVoiceCommands(_ enabled: Bool) {
        saveTopLevelRawField("voice-commands", rawValue: enabled ? "true" : "false")
    }

    /// Writes (or updates) the "silence-threshold" field in config.jsonc.
    static func saveSilenceThreshold(_ value: Double) {
        saveTopLevelRawField("silence-threshold", rawValue: String(format: "%.4f", value))
    }

    /// Writes (or updates) the "prefix" field in config.jsonc.
    static func savePrefix(_ value: String) {
        saveTopLevelStringField("prefix", value: value)
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
