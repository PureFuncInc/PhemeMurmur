import AVFoundation
import Foundation
import Speech

/// On-device speech recognition using macOS 26's SpeechAnalyzer.
/// No API key, no network, no per-request cost. Language model assets are downloaded
/// once per locale on first use.
///
/// Uses `DictationTranscriber` rather than `SpeechTranscriber`: this app is a
/// dictation tool — press a key, say a sentence, have it typed into whatever is
/// in front of you — which is exactly what that module is built for, and it is
/// the only one of the two with a `shortForm` content hint or any punctuation
/// control at all.
///
/// The live preview in `LiveSpeechTranscriber` deliberately still runs
/// `SpeechTranscriber`. Its `.fastResults` option has no equivalent here, and
/// the snappy partial text is the point of the preview. The two passes were
/// already independent recognitions of the same audio, and the HUD shows this
/// pass's text once the recording is over, so nothing the user sees disagrees.
@available(macOS 26.0, *)
struct AppleSpeechProvider: TranscriptionProvider {
    static let modelIdentifier = "apple-speech-on-device"

    let modelName: String

    init(model: String = Self.modelIdentifier) {
        self.modelName = model
    }

    var isKeyConfigured: Bool { true }

    func transcribe(fileURL: URL, language: String?, prompt: String?) async throws -> String {
        if prompt != nil {
            throw AppleSpeechError.promptNotSupported
        }

        let locale = Self.resolveLocale(from: language)

        let supported = await DictationTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            throw AppleSpeechError.localeUnsupported(locale.identifier)
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            // Recordings here are a sentence or two, not a lecture.
            contentHints: [.shortForm],
            // Punctuation stays off: the app strips full-width marks anyway, so
            // asking for them would only be work thrown away. Adding
            // `.punctuation` here and dropping `TranscriptPunctuation.strip` is
            // the whole change if that ever becomes wanted.
            transcriptionOptions: [],
            // This pass reads a finished file, so there is nothing to report
            // progressively.
            reportingOptions: [],
            attributeOptions: []
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let collected: String = {
            var buffer = ""
            for try await result in transcriber.results {
                buffer += String(result.text.characters)
            }
            return buffer
        }()

        let audioFile = try AVAudioFile(forReading: fileURL)
        if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        var text = try await collected

        // Safeguard against Simplified output for zh locales, matching OpenAI
        // provider behavior. Character-level only; ambiguous mappings unchanged.
        if locale.language.languageCode?.identifier == "zh",
           let converted = text.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) {
            text = converted
        }

        // This recogniser only ever produces full stops, so its punctuation is
        // dropped rather than left half-done. The cloud providers punctuate
        // properly and keep theirs.
        text = TranscriptPunctuation.strip(text)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "__SILENCE__"
        }
        return trimmed
    }

    private static func resolveLocale(from language: String?) -> Locale {
        guard let language, !language.isEmpty else { return .current }
        switch language.lowercased() {
        case "zh", "zh-tw", "zh-hant":
            return Locale(identifier: "zh-TW")
        case "zh-cn", "zh-hans":
            return Locale(identifier: "zh-CN")
        case "en":
            return Locale(identifier: "en-US")
        default:
            return Locale(identifier: language)
        }
    }
}

enum AppleSpeechError: Error, LocalizedError {
    case promptNotSupported
    case localeUnsupported(String)
    case requiresMacOS26

    var errorDescription: String? {
        switch self {
        case .promptNotSupported:
            return "Apple provider does not support post-processing prompts. Choose a template without a 'prompt' field, or switch to OpenAI/Gemini."
        case .localeUnsupported(let id):
            return "Apple Speech does not support locale \(id) on this device."
        case .requiresMacOS26:
            return "Apple provider requires macOS 26 or later."
        }
    }
}
