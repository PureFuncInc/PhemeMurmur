import Foundation

/// Strips the punctuation Apple's on-device recogniser inserts.
///
/// `SpeechTranscriber` has no punctuation control at all — its only
/// `TranscriptionOption` is `.etiquetteReplacements` — and in practice it emits
/// a full stop and nothing else: no commas, no question marks. Half-punctuated
/// text is worse than none, so the marks come out and the user punctuates as
/// they like.
///
/// Pure and free of any Speech dependency, so it can be unit tested and so it
/// compiles on macOS versions that have no on-device recognition at all.
enum TranscriptPunctuation {

    /// Full-width CJK marks only. ASCII punctuation is deliberately left alone:
    /// it carries meaning in dictated numbers, versions and URLs, where losing
    /// a period would turn "v1.2" into "v12".
    private static let marks: Set<Character> = [
        "。", "，", "、", "；", "：", "？", "！",
    ]

    /// Removes the marks and closes the gaps they leave behind.
    ///
    /// Does not trim the ends: the live preview feeds this one recognised chunk
    /// at a time and concatenates the results, so a leading space at a chunk
    /// boundary is the only thing keeping two English words apart.
    static func strip(_ text: String) -> String {
        guard text.contains(where: marks.contains) else { return text }
        let cleaned = String(text.filter { !marks.contains($0) })
        // A mark sitting between two Latin words leaves a doubled space behind.
        return cleaned.replacingOccurrences(of: "[ \\t]{2,}", with: " ",
                                            options: .regularExpression)
    }
}
