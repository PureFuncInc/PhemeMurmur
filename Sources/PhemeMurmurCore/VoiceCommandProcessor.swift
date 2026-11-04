import Foundation

/// Formatting commands that can be turned on one by one, named as they are written in config.json's `voice-commands`.
public enum VoiceCommand: String, CaseIterable, Decodable, Sendable {
    case newLine        = "new-line"
    case blankLine      = "blank-line"
    case divider        = "divider"
    case numberedPoints = "numbered-points"

    public init(from decoder: Decoder) throws {
        self = try decoder.decodeCase(of: Self.self)
    }

    /// What to say, as shown in the menu.
    public var displayName: String {
        switch self {
        case .newLine:        return "換一行"
        case .blankLine:      return "空一行"
        case .divider:        return "分隔線"
        case .numberedPoints: return "第一點…第十點"
        }
    }

    var replacements: [(trigger: String, output: String)] {
        switch self {
        case .newLine:
            return [("換一行", "\n")]
        case .blankLine:
            return [("空一行", "\n\n")]
        case .divider:
            return [("分隔線", "\n\n---\n\n")]
        case .numberedPoints:
            return [
                ("第一點", "\n1. "),
                ("第二點", "\n2. "),
                ("第三點", "\n3. "),
                ("第四點", "\n4. "),
                ("第五點", "\n5. "),
                ("第六點", "\n6. "),
                ("第七點", "\n7. "),
                ("第八點", "\n8. "),
                ("第九點", "\n9. "),
                ("第十點", "\n10. "),
            ]
        }
    }
}

public enum VoiceCommandProcessor {
    private static let boundaryClass = "[ \\t\\u3000，。、,.]*"

    /// Applies the given commands to `text`; with none, `text` comes back unchanged.
    public static func process(_ text: String, commands: Set<VoiceCommand>) -> String {
        // Walk `allCases` rather than the set so replacements always run in the same order.
        let allTriggers = VoiceCommand.allCases
            .filter(commands.contains)
            .flatMap(\.replacements)
            .sorted { $0.trigger.count > $1.trigger.count }

        var result = text
        for (trigger, output) in allTriggers {
            let escapedTrigger = NSRegularExpression.escapedPattern(for: trigger)
            let pattern = "\(boundaryClass)\(escapedTrigger)\(boundaryClass)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: output)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: template
            )
        }
        return result
    }
}
