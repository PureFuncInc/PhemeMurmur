import Foundation

enum VoiceCommandProcessor {
    private static let staticReplacements: [(trigger: String, output: String)] = [
        ("換行", "\n"),
        ("空行", "\n\n"),
        ("分隔線", "\n\n---\n\n"),
    ]

    private static let numberedPoints: [(trigger: String, output: String)] = [
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

    private static let boundaryClass = "[ \\t\\u3000，。、,.]*"

    static func process(_ text: String) -> String {
        let allTriggers = (staticReplacements + numberedPoints)
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
