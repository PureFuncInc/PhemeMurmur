import Foundation

struct PromptTemplate: Decodable {
    let language: String?
    let prompt: String?
}

struct ConfigFile: Decodable {
    let apiKey: String
    let prefix: String?
    let transcriptionModel: String?
    let promptTemplates: [String: PromptTemplate]?

    enum CodingKeys: String, CodingKey {
        case apiKey = "openai-api-key"
        case prefix
        case transcriptionModel = "transcription-model"
        case promptTemplates = "prompt-templates"
    }
}

enum Config {
    static let sampleRate: Double = 16000
    static let channels: UInt32 = 1
    static let minDuration: Double = 0.5
    static let debounceInterval: Double = 0.4

    static let defaultPromptTemplateName = "traditional-chinese"

    static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/pheme-murmur/config.jsonc"
    }()

    static let defaultConfigContent = """
{
    // Your OpenAI API key — get one at https://platform.openai.com/api-keys
    "openai-api-key": "sk-your-key-here",

    // Optional: text to prepend before every transcription result
    // "prefix": "",

    // Transcription model. Default is Mini (cheaper & faster).
    // For higher accuracy, switch to "gpt-4o-transcribe".
    "transcription-model": "gpt-4o-mini-transcribe-2025-12-15",

    // Prompt templates — switchable from the menu bar.
    //   "language": input audio language (ISO-639-1), helps transcription accuracy
    //   "prompt": if set, sends transcribed text through Chat API for post-processing
    "prompt-templates": {
        "traditional-chinese": { "language": "zh" },
        "to-english": { "language": "zh", "prompt": "Translate the following text to English. Output ONLY the English translation, nothing else." }
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
