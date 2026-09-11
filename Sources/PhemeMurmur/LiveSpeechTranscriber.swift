import AVFoundation
import Foundation
import Speech

/// Streaming counterpart to `AppleSpeechProvider`: the same SpeechAnalyzer +
/// SpeechTranscriber pair, but fed from a live `AsyncStream` of microphone
/// buffers instead of a finished file, and asked for volatile (not yet final)
/// results so the HUD can show text while the user is still talking.
///
/// This is a *preview only*. The text that actually gets pasted still comes from
/// the normal provider path running over the recorded WAV.
@available(macOS 26.0, *)
final class LiveSpeechTranscriber {

    /// Called on the main thread whenever the best-known text changes.
    private let onText: (String) -> Void

    /// Everything below is touched from three places — the main thread
    /// (start/stop), the realtime audio tap (feed), and the analyzer task — so it
    /// is guarded by a lock, matching `AudioRecorder`'s style. The lock is only
    /// ever held for a pointer assignment; never across an await or a dispatch.
    private let lock = NSLock()
    /// Raw recorder buffers (16 kHz mono Float32) handed over by the audio tap.
    /// Bounded so a stalled analyzer can never grow this without limit; dropping
    /// the oldest buffers degrades the preview, never the recording.
    private var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var pumpTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Never>?

    init(onText: @escaping (String) -> Void) {
        self.onText = onText
    }

    /// Starts the analyzer in the background. Returns immediately: recording must
    /// never wait on locale checks or model assets. If anything is missing the
    /// preview simply never produces text.
    func start(language: String?) {
        let (bufferStream, bufferContinuation) = Self.makeStream(of: AVAudioPCMBuffer.self)
        let (inputStream, inputContinuation) = Self.makeStream(of: AnalyzerInput.self)
        lock.lock()
        self.bufferContinuation = bufferContinuation
        self.inputContinuation = inputContinuation
        lock.unlock()

        let locale = Self.resolveLocale(from: language)
        let emit = onText

        let task = Task { [weak self] in
            guard let transcriber = await Self.makeTranscriber(locale: locale) else {
                self?.finishStreams()
                return
            }

            // Convert recorder buffers into whatever format the analyzer wants,
            // off the realtime audio thread.
            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            let pump = Task {
                let converter = Self.makeConverter(to: analyzerFormat)
                for await buffer in bufferStream {
                    if Task.isCancelled { break }
                    guard let prepared = Self.convert(buffer, using: converter, to: analyzerFormat) else { continue }
                    inputContinuation.yield(AnalyzerInput(buffer: prepared))
                }
                inputContinuation.finish()
            }
            self?.store(pumpTask: pump)

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let isChinese = locale.language.languageCode?.identifier == "zh"

            // Subscribe to results *before* starting the analyzer, exactly as the
            // file-based provider does, and as a structured child task so that
            // cancelling this one tears the consumer down with it.
            async let consumed: Void = {
                var accumulated = LiveTranscriptText()
                do {
                    for try await result in transcriber.results {
                        var text = String(result.text.characters)
                        if isChinese,
                           let converted = text.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) {
                            text = converted
                        }
                        // Same rule as the final pass, so the preview and the
                        // pasted text cannot disagree about punctuation.
                        text = TranscriptPunctuation.strip(text)
                        // Volatile results cover only the not-yet-committed tail,
                        // so the preview is "everything finalised" + "current guess".
                        if result.isFinal {
                            accumulated.appendFinalized(text)
                        } else {
                            accumulated.setVolatile(text)
                        }
                        let display = accumulated.display
                        await MainActor.run { emit(display) }
                    }
                } catch {
                    print("Live preview stopped: \(error)")
                }
            }()
            do {
                // Preloads the model so the first words are not lost to setup.
                try await analyzer.prepareToAnalyze(in: analyzerFormat)
                try await analyzer.start(inputSequence: inputStream)
            } catch {
                print("Live preview could not start: \(error)")
            }
            await consumed
            await analyzer.cancelAndFinishNow()
        }
        lock.lock()
        analyzerTask = task
        lock.unlock()
    }

    private func store(pumpTask task: Task<Void, Never>) {
        lock.lock()
        pumpTask = task
        lock.unlock()
    }

    /// Called from the realtime audio tap. Must stay allocation-light and must
    /// never block: `yield` on a buffered AsyncStream continuation does neither.
    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let continuation = bufferContinuation
        lock.unlock()
        continuation?.yield(buffer)
    }

    /// Tears everything down. Safe to call more than once and from any recording
    /// end path (stop, cancel, early return, quit).
    func stop() {
        finishStreams()
        lock.lock()
        let pump = pumpTask
        let analyzer = analyzerTask
        pumpTask = nil
        analyzerTask = nil
        lock.unlock()
        pump?.cancel()
        analyzer?.cancel()
    }

    private func finishStreams() {
        lock.lock()
        let buffers = bufferContinuation
        let inputs = inputContinuation
        bufferContinuation = nil
        inputContinuation = nil
        lock.unlock()
        buffers?.finish()
        inputs?.finish()
    }

    // MARK: - Setup helpers

    private static func makeStream<T>(of _: T.Type) -> (AsyncStream<T>, AsyncStream<T>.Continuation) {
        var continuation: AsyncStream<T>.Continuation!
        let stream = AsyncStream<T>(bufferingPolicy: .bufferingNewest(64)) { continuation = $0 }
        return (stream, continuation)
    }

    /// Builds a transcriber that reports volatile results, but only if the locale
    /// is supported *and* its assets are already installed. Downloading a model
    /// mid-recording would be a surprise multi-hundred-megabyte fetch, so the
    /// preview just stays silent and `AppleSpeechProvider` handles the download
    /// on the real transcription instead.
    private static func makeTranscriber(locale: Locale) async -> SpeechTranscriber? {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            return nil
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
        // `SpeechTranscriber.installedLocales` is the only reliable "assets are
        // on disk" signal: `AssetInventory.status(forModules:)` reports
        // `.supported` even for locales that are demonstrably installed.
        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            print("Live preview skipped: assets for \(locale.identifier) not installed yet.")
            return nil
        }
        return transcriber
    }

    private static var recorderFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: Config.sampleRate,
                      channels: AVAudioChannelCount(Config.channels),
                      interleaved: false)
    }

    private static func makeConverter(to analyzerFormat: AVAudioFormat?) -> AVAudioConverter? {
        guard let analyzerFormat, let recorderFormat else { return nil }
        if analyzerFormat.isEqual(recorderFormat) { return nil }
        return AVAudioConverter(from: recorderFormat, to: analyzerFormat)
    }

    private static func convert(_ buffer: AVAudioPCMBuffer,
                                using converter: AVAudioConverter?,
                                to analyzerFormat: AVAudioFormat?) -> AVAudioPCMBuffer? {
        guard let converter, let analyzerFormat else { return buffer }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    /// Mirrors `AppleSpeechProvider.resolveLocale` so the preview and the real
    /// transcription always run the same language.
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
