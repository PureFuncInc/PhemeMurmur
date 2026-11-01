import Foundation

public struct PromptTemplate: Decodable, Sendable {
    public let language: String?
    public let prompt: String?
    public let enabled: Bool?
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
    public let postProcess: PostProcessConfig?
    public let enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case postProcess = "post-process"
        case enabled
    }
}

public struct ConfigFile: Decodable {
    public let providers: [String: ProviderEntry]?
    public let prefix: String?
    public let promptTemplates: [String: PromptTemplate]?
    public let hotkey: String?
    public let silenceThreshold: Double?
    public let voiceCommands: Bool?

    enum CodingKeys: String, CodingKey {
        case providers
        case prefix
        case promptTemplates = "prompt-templates"
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

    /// Resolves the default active provider name: the entry marked `"enabled": true`,
    /// otherwise the first sorted key.
    public var resolvedActiveProvider: String? {
        let resolved = resolvedProviders
        let enabled = resolved.filter { $0.value.enabled == true }.keys.sorted()
        return enabled.first ?? resolved.keys.sorted().first
    }

    /// The prompt template marked `"enabled": true`, if any.
    public var resolvedActivePromptTemplate: String? {
        (promptTemplates ?? [:]).filter { $0.value.enabled == true }.keys.sorted().first
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
        "Apple": { "enabled": true, "type": "apple" },
        "OpenAI": { "type": "openai" }
    },
    "hotkey": "right-shift",
    "prefix": "",
    "silence-threshold": 0,
    "prompt-templates": {
        "zh_TW": { "enabled": true, "language": "zh" },
        "zh_TW-en_US": { "language": "zh", "prompt": "Translate the following text to English. Output ONLY the English translation, nothing else." }
    },
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
        print("Pick OpenAI from the Provider menu to enter an API key.")
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

    /// Marks the provider with `"enabled": true` in config.json and clears it from the others.
    public static func saveActiveProvider(_ name: String) {
        saveEnabledEntry(name, inSection: "providers")
    }

    /// Marks the prompt template with `"enabled": true` in config.json and clears it from the others.
    public static func saveActivePromptTemplate(_ name: String) {
        saveEnabledEntry(name, inSection: "prompt-templates")
    }

    private static func saveEnabledEntry(_ name: String, inSection section: String) {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8),
              let updated = enablingEntry(name, inSection: section, of: content) else { return }
        try? updated.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Returns `content` with `"enabled": true` on the `name` entry of the top-level `section`
    /// object and the `enabled` key removed from its siblings. All other text is left untouched
    /// so the file keeps its formatting and key order. Returns nil if the entry isn't found.
    static func enablingEntry(_ name: String, inSection section: String, of content: String) -> String? {
        var bytes = Array(content.utf8)
        let scanner = JSONScanner(bytes: bytes)
        guard (try? JSONSerialization.jsonObject(with: Data(bytes))) != nil,
              let root = scanner.members(ofObjectAt: scanner.skipWhitespace(0)),
              let sectionValue = root.last(where: { $0.key == section })?.value,
              let entries = scanner.members(ofObjectAt: sectionValue.lowerBound),
              let target = entries.last(where: { $0.key == name }),
              scanner.members(ofObjectAt: target.value.lowerBound) != nil
        else { return nil }

        var edits: [(range: Range<Int>, text: String)] = []
        for entry in entries {
            guard let fields = scanner.members(ofObjectAt: entry.value.lowerBound) else { continue }
            let index = fields.firstIndex { $0.key == "enabled" }
            if entry.keyStart == target.keyStart {
                if let index {
                    edits.append((fields[index].value, "true"))
                } else {
                    // Prepend, reusing the whitespace after `{` so single- and multi-line entries both stay tidy.
                    let open = entry.value.lowerBound + 1
                    let first = scanner.skipWhitespace(open)
                    let gap = String(decoding: bytes[open..<first], as: UTF8.self)
                    edits.append(fields.isEmpty
                        ? (open..<first, " \"enabled\": true ")
                        : (open..<open, gap + "\"enabled\": true,"))
                }
            } else if let index {
                // Drop the field together with exactly one adjacent comma.
                let field = fields[index]
                if index + 1 < fields.count {
                    edits.append((field.keyStart..<fields[index + 1].keyStart, ""))
                } else if index > 0 {
                    edits.append((fields[index - 1].value.upperBound..<field.value.upperBound, ""))
                } else {
                    edits.append((entry.value.lowerBound + 1..<entry.value.upperBound - 1, ""))
                }
            }
        }
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: Array(edit.text.utf8))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func loadConfig() -> ConfigFile? {
        guard let data = FileManager.default.contents(atPath: configPath) else { return nil }
        return try? JSONDecoder().decode(ConfigFile.self, from: data)
    }
}

/// Minimal JSON walker that reports where object members sit in the raw bytes,
/// so config.json can be edited in place. Assumes well-formed input.
private struct JSONScanner {
    struct Member {
        let key: String
        let keyStart: Int
        let value: Range<Int>
    }

    let bytes: [UInt8]

    func skipWhitespace(_ start: Int) -> Int {
        var i = start
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        return i
    }

    /// The members of the object whose `{` is at `start`, or nil if there is no object there.
    func members(ofObjectAt start: Int) -> [Member]? {
        guard start < bytes.count, bytes[start] == UInt8(ascii: "{") else { return nil }
        var members: [Member] = []
        var i = skipWhitespace(start + 1)
        while i < bytes.count, bytes[i] == UInt8(ascii: "\"") {
            let keyEnd = endOfValue(at: i)
            let key = (try? JSONDecoder().decode(String.self, from: Data(bytes[i..<keyEnd]))) ?? ""
            let colon = skipWhitespace(keyEnd)
            guard colon < bytes.count, bytes[colon] == UInt8(ascii: ":") else { break }
            let valueStart = skipWhitespace(colon + 1)
            let valueEnd = endOfValue(at: valueStart)
            members.append(Member(key: key, keyStart: i, value: valueStart..<valueEnd))
            let next = skipWhitespace(valueEnd)
            guard next < bytes.count, bytes[next] == UInt8(ascii: ",") else { break }
            i = skipWhitespace(next + 1)
        }
        return members
    }

    /// The index just past the string, object, array, or literal starting at `start`.
    func endOfValue(at start: Int) -> Int {
        var depth = 0
        var i = start
        while i < bytes.count {
            switch bytes[i] {
            case UInt8(ascii: "\""):
                i += 1
                while i < bytes.count, bytes[i] != UInt8(ascii: "\"") {
                    i += bytes[i] == UInt8(ascii: "\\") ? 2 : 1
                }
                i = min(i + 1, bytes.count)
                if depth == 0 { return i }
                continue
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                if depth == 0 { return i }
                depth -= 1
                if depth == 0 { return i + 1 }
            case UInt8(ascii: ","), 0x20, 0x09, 0x0A, 0x0D:
                if depth == 0 { return i }
            default:
                break
            }
            i += 1
        }
        return bytes.count
    }
}
