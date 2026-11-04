import Foundation

public struct PromptTemplate: Decodable, Sendable {
    public let language: String?
    public let prompt: String?
    public let active: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case language
        case prompt
        case active
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
    }
}

/// What a provider runs on, implied by its name in config.json: `"Apple"` is on-device speech
/// recognition, and any other name is an OpenAI account whose API key is in the Keychain under that name.
public enum ProviderType: Sendable {
    case openai
    case apple

    public init(providerName: String) {
        self = providerName == "Apple" ? .apple : .openai
    }
}

/// Modifier keys that can toggle recording, named as they are written in config.json.
public enum HotkeyKey: String, CaseIterable, Decodable, Sendable {
    case fn           = "fn"
    case rightCommand = "right-command"
    case rightOption  = "right-option"
    case rightControl = "right-control"
    case rightShift   = "right-shift"

    public init(from decoder: Decoder) throws {
        self = try decoder.decodeCase(of: Self.self)
    }
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

public struct ProviderEntry: Decodable {
    public let active: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case active
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
    }
}

public struct ConfigFile: Decodable {
    /// Every provider the menu offers, keyed by name; see `ProviderType(providerName:)`.
    public let providers: [String: ProviderEntry]
    public let prefix: String?
    public let promptTemplates: [String: PromptTemplate]?
    public let hotkey: HotkeyKey?
    /// The voice commands turned on; each is opted into separately.
    public let voiceCommands: [VoiceCommand]?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case providers
        case prefix
        case promptTemplates = "prompt-templates"
        case hotkey
        case voiceCommands = "voice-commands"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providers = try container.decode([String: ProviderEntry].self, forKey: .providers)
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix)
        promptTemplates = try container.decodeIfPresent([String: PromptTemplate].self, forKey: .promptTemplates)
        hotkey = try container.decodeIfPresent(HotkeyKey.self, forKey: .hotkey)
        do {
            voiceCommands = try container.decodeIfPresent([VoiceCommand].self, forKey: .voiceCommands)
        } catch DecodingError.typeMismatch, DecodingError.valueNotFound {
            // Also catches the old `true` / `false`, so spell out what the value looks like now.
            let all = VoiceCommand.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: .voiceCommands, in: container,
                debugDescription: "expected an array of the commands to turn on, e.g. [\(all)], or [] for none"
            )
        } catch DecodingError.dataCorrupted(let context) {
            // An unknown command: name `voice-commands` rather than the element's path, `voice-commands.Index 0`.
            throw DecodingError.dataCorruptedError(
                forKey: .voiceCommands, in: container,
                debugDescription: context.debugDescription
            )
        }

        var seenVoiceCommands: Set<VoiceCommand> = []
        for command in voiceCommands ?? [] where !seenVoiceCommands.insert(command).inserted {
            throw DecodingError.dataCorruptedError(
                forKey: .voiceCommands, in: container,
                debugDescription: "\"\(command.rawValue)\" is listed more than once"
            )
        }

        if providers.isEmpty {
            throw DecodingError.dataCorruptedError(
                forKey: .providers, in: container,
                debugDescription: "needs at least one entry, e.g. \"Apple\": {} or \"OpenAI\": {}"
            )
        }
        let activeEntries: [(CodingKeys, [String])] = [
            (.providers, providers.filter { $0.value.active == true }.keys.sorted()),
            (.promptTemplates, (promptTemplates ?? [:]).filter { $0.value.active == true }.keys.sorted()),
        ]
        for (section, names) in activeEntries where names.count > 1 {
            throw DecodingError.dataCorruptedError(
                forKey: section, in: container,
                debugDescription: "only one entry can have \"active\": true, found \(names.joined(separator: ", "))"
            )
        }
    }

    public var resolvedHotkey: HotkeyKey {
        hotkey ?? .rightShift
    }

    /// Resolves the default active provider name: the entry marked `"active": true`,
    /// otherwise the first sorted key.
    public var resolvedActiveProvider: String? {
        let active = providers.filter { $0.value.active == true }.keys.sorted()
        return active.first ?? providers.keys.sorted().first
    }

    /// The prompt template marked `"active": true`, if any.
    public var resolvedActivePromptTemplate: String? {
        (promptTemplates ?? [:]).filter { $0.value.active == true }.keys.sorted().first
    }

    /// Defaults to none: each command must be explicitly opted into.
    public var resolvedVoiceCommands: Set<VoiceCommand> {
        Set(voiceCommands ?? [])
    }
}

/// Why config.json can't be used, worded for someone fixing it by hand: it names the key path
/// (e.g. `providers.OpenAI.active`) or, for malformed JSON, the line and column.
public struct ConfigError: LocalizedError {
    public let message: String

    public var errorDescription: String? { message }

    public init(message: String) {
        self.message = message
    }

    init(_ error: DecodingError) {
        func at(_ path: [CodingKey]) -> String {
            path.isEmpty ? "config.json" : path.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            // Foundation reports where the syntax error is in the underlying error.
            let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            message = "Invalid JSON: \(detail ?? context.debugDescription)"
        case .dataCorrupted(let context):
            message = "\(at(context.codingPath)): \(context.debugDescription)"
        case .typeMismatch(let type, let context):
            message = "\(at(context.codingPath)): expected \(Self.jsonType(type))"
        case .valueNotFound(let type, let context):
            message = "\(at(context.codingPath)): expected \(Self.jsonType(type)), found null"
        case .keyNotFound(let key, let context):
            message = "\(at(context.codingPath)): missing \"\(key.stringValue)\""
        @unknown default:
            message = error.localizedDescription
        }
    }

    private static func jsonType(_ type: Any.Type) -> String {
        switch type {
        case is Bool.Type:   return "true or false"
        case is String.Type: return "a string"
        default:             return "an object"
        }
    }
}

/// Matches any key, so a decoder can list every key present in a JSON object.
private struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Decoder {
    /// Throws on a key `Keys` doesn't list, so a typo like `"actve"` is reported instead of silently ignored.
    func rejectUnknownKeys<Keys: CodingKey & CaseIterable>(_: Keys.Type) throws {
        let container = try container(keyedBy: AnyCodingKey.self)
        let known = Set(Keys.allCases.map(\.stringValue))
        let unknown = container.allKeys.filter { !known.contains($0.stringValue) }
        if let first = unknown.min(by: { $0.stringValue < $1.stringValue }) {
            throw DecodingError.dataCorruptedError(forKey: first, in: container, debugDescription: "unknown key")
        }
    }

    /// Decodes a string that must be one of `T`'s raw values, listing the allowed ones when it isn't.
    func decodeCase<T: RawRepresentable & CaseIterable>(of _: T.Type) throws -> T where T.RawValue == String {
        let container = try singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = T(rawValue: raw) else {
            let allowed = T.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\"\(raw)\" is not one of \(allowed)")
        }
        return value
    }
}

public enum Config {
    public static let sampleRate: Double = 16000
    public static let channels: UInt32 = 1
    public static let minDuration: Double = 0.5
    public static let debounceInterval: Double = 0.4

    public static let defaultPromptTemplateName = "zh_TW"

    public static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/pheme-murmur/config.json"
    }()

    static let defaultConfigContent = """
{
    "providers": {
        "Apple": { "active": true },
        "OpenAI": {}
    },
    "hotkey": "right-shift",
    "prefix": "",
    "prompt-templates": {
        "zh_TW": { "active": true, "language": "zh" },
        "zh_TW-en_US": { "language": "zh", "prompt": "Translate the following text to English. Output ONLY the English translation, nothing else." }
    },
    "voice-commands": []
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

    /// Marks the provider with `"active": true` in config.json and clears it from the others.
    public static func saveActiveProvider(_ name: String) {
        saveActiveEntry(name, inSection: "providers")
    }

    /// Marks the prompt template with `"active": true` in config.json and clears it from the others.
    public static func saveActivePromptTemplate(_ name: String) {
        saveActiveEntry(name, inSection: "prompt-templates")
    }

    /// Writes (or updates) the "voice-commands" field in config.json, preserving all other content.
    public static func saveVoiceCommands(_ commands: Set<VoiceCommand>) {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8),
              let updated = settingVoiceCommands(commands, of: content) else { return }
        try? updated.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Returns `content` with the top-level "voice-commands" value replaced by `commands`, listed in
    /// `VoiceCommand.allCases` order, or added after `{` if the key is missing. Whatever the old value
    /// was (including the old `true` / `false`) is overwritten, and all other text is left untouched.
    /// Returns nil if `content` isn't a JSON object.
    static func settingVoiceCommands(_ commands: Set<VoiceCommand>, of content: String) -> String? {
        var bytes = Array(content.utf8)
        let scanner = JSONScanner(bytes: bytes)
        let rootStart = scanner.skipWhitespace(0)
        guard (try? JSONSerialization.jsonObject(with: Data(bytes))) != nil,
              let root = scanner.members(ofObjectAt: rootStart)
        else { return nil }

        let names = VoiceCommand.allCases.filter(commands.contains).map { "\"\($0.rawValue)\"" }
        let value = "[\(names.joined(separator: ", "))]"
        if let existing = root.last(where: { $0.key == "voice-commands" }) {
            bytes.replaceSubrange(existing.value, with: Array(value.utf8))
        } else {
            let entry = "\n    \"voice-commands\": \(value)" + (root.isEmpty ? "\n" : ",")
            bytes.insert(contentsOf: Array(entry.utf8), at: rootStart + 1)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func saveActiveEntry(_ name: String, inSection section: String) {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8),
              let updated = activatingEntry(name, inSection: section, of: content) else { return }
        try? updated.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Returns `content` with `"active": true` on the `name` entry of the top-level `section`
    /// object and the `active` key removed from its siblings. All other text is left untouched
    /// so the file keeps its formatting and key order. Returns nil if the entry isn't found.
    static func activatingEntry(_ name: String, inSection section: String, of content: String) -> String? {
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
            let index = fields.firstIndex { $0.key == "active" }
            if entry.keyStart == target.keyStart {
                if let index {
                    edits.append((fields[index].value, "true"))
                } else {
                    // Prepend, reusing the whitespace after `{` so single- and multi-line entries both stay tidy.
                    let open = entry.value.lowerBound + 1
                    let first = scanner.skipWhitespace(open)
                    let gap = String(decoding: bytes[open..<first], as: UTF8.self)
                    edits.append(fields.isEmpty
                        ? (open..<first, " \"active\": true ")
                        : (open..<open, gap + "\"active\": true,"))
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

    /// Decodes the contents of config.json. Anything a hand edit can get wrong (malformed JSON,
    /// unknown keys, wrong value types, unsupported values) throws a `ConfigError` here, so a
    /// config that parses is safe to apply.
    public static func parse(_ data: Data) throws -> ConfigFile {
        do {
            return try JSONDecoder().decode(ConfigFile.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError(error)
        }
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
