import AVFoundation
import Foundation
import Speech

/// Streaming counterpart to `AppleSpeechProvider`: the same SpeechAnalyzer and
/// DictationTranscriber pair, but fed from a live `AsyncStream` of microphone
/// buffers instead of a finished file, and asked for volatile (not yet final)
/// results so the HUD can show text while the user is still talking.
///
/// This is no longer a preview. What it recognises is what gets pasted, and
/// `AppleSpeechProvider` only runs over the recorded WAV as a fallback when
/// this produced nothing at all. Re-recognising the file afterwards meant the
/// text changed after the user had already read it, which reads worse than the
/// small accuracy a second pass buys. Everything here is therefore sized for
/// being the answer rather than a guess: no dropped buffers, no clipped text,
/// and a finalisation on the way out rather than a cancel.
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
    /// Everything recognised so far. Lives on the instance rather than inside
    /// the consumer closure because `finish()` has to hand it back as the text
    /// to paste.
    private var accumulated = LiveTranscriptText()

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
            // Bound once here: referring to the captured `self` from inside the
            // concurrently-running consumer is an error under Swift 6.
            let owner = self
            async let consumed: Void = {
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
                        let display: String = {
                            guard let owner else { return "" }
                            owner.lock.lock()
                            defer { owner.lock.unlock() }
                            if result.isFinal {
                                owner.accumulated.appendFinalized(text)
                            } else {
                                owner.accumulated.setVolatile(text)
                            }
                            return owner.accumulated.display
                        }()
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
                // `start` returns once the input is exhausted. Finalising here
                // rather than cancelling is what keeps the last words spoken:
                // cancelling discards whatever the analyzer had not yet emitted.
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                print("Live transcription stopped early: \(error)")
                await analyzer.cancelAndFinishNow()
            }
            await consumed
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

    /// Ends the recording cleanly and returns everything that was recognised.
    ///
    /// Unlike ``stop()`` this waits for the analyzer to finalise instead of
    /// cancelling it, which is the difference between keeping and losing the
    /// last words spoken. Returns an empty string when the preview never got
    /// going — an unsupported locale, assets not installed — so the caller can
    /// fall back to transcribing the recorded file.
    func finish() async -> String {
        finishStreams()
        // The lock is taken in synchronous helpers: NSLock must not be held
        // across an await, and Swift 6 rejects locking from an async context.
        let (pump, analyzer) = takeTasks()
        await pump?.value
        await analyzer?.value
        return drainAccumulated()
    }

    private func takeTasks() -> (Task<Void, Never>?, Task<Void, Never>?) {
        lock.lock()
        defer { lock.unlock() }
        let tasks = (pumpTask, analyzerTask)
        pumpTask = nil
        analyzerTask = nil
        return tasks
    }

    private func drainAccumulated() -> String {
        lock.lock()
        defer { lock.unlock() }
        let text = accumulated.full
        accumulated.reset()
        return text
    }

    /// Tears everything down without waiting. For the paths that are throwing
    /// the audio away anyway — Esc, quit — where the recognised text is not
    /// wanted and blocking on finalisation would only add lag.
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

        lock.lock()
        accumulated.reset()
        lock.unlock()
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
        // Unbounded on purpose. This used to drop the oldest buffers so a stalled
        // analyzer could only degrade a preview, but the recognised text is now
        // what gets pasted, so a dropped buffer is a lost word. A dictation-length
        // recording of 16 kHz mono float is a few megabytes at worst.
        let stream = AsyncStream<T>(bufferingPolicy: .unbounded) { continuation = $0 }
        return (stream, continuation)
    }

    /// Builds a transcriber that reports volatile results, but only if the locale
    /// is supported *and* its assets are already installed. Downloading a model
    /// mid-recording would be a surprise multi-hundred-megabyte fetch, so the
    /// preview just stays silent and `AppleSpeechProvider` handles the download
    /// on the real transcription instead.
    ///
    /// `DictationTranscriber`, matching `AppleSpeechProvider`. Measured on a
    /// 27-second zh-TW sample, transcribing the same audio as a stream:
    ///
    ///     SpeechTranscriber + .fastResults   95.2%  (界麵, 機製, 轉確度)
    ///     DictationTranscriber              100.0%
    ///
    /// `.fastResults` was buying latency at the cost of exactly the kind of
    /// error a dictation tool cannot afford, now that this text is what gets
    /// pasted. `.frequentFinalization` is the dictation module's way of keeping
    /// the preview lively, and it cost nothing in accuracy on the same sample.
    private static func makeTranscriber(locale: Locale) async -> DictationTranscriber? {
        let supported = await DictationTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            return nil
        }
        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [.shortForm],
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .frequentFinalization],
            attributeOptions: []
        )
        // `installedLocales` is the only reliable "assets are on disk" signal:
        // `AssetInventory.status(forModules:)` reports `.supported` even for
        // locales that are demonstrably installed.
        let installed = await DictationTranscriber.installedLocales
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
