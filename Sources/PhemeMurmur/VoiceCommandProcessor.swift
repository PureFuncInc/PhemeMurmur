import Foundation

enum VoiceCommandProcessor {
    private static let staticReplacements: [(trigger: String, output: String)] = [
        ("換行", "\n"),
        ("空行", "\n\n"),
        ("分隔線", "\n\n---\n\n"),
    ]

    private static let numberedPoints: [(trigger: String, output: String)] = []

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
