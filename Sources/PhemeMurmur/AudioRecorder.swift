import AVFoundation
import Foundation

final class AudioRecorder {
    /// Created fresh for every recording and dropped on stop. A long-lived engine
    /// stays bound to whichever input device was default when it was first used;
    /// once that device disappears (Bluetooth headset off, USB mic unplugged,
    /// virtual device removed) its input node reports a dead format and the next
    /// installTap raises an uncatchable Objective-C exception.
    private var engine: AVAudioEngine?
    private var buffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    /// Emits `beamCount` amplitude values on the main thread while recording,
    /// throttled to roughly 30Hz. Nil when nothing is observing.
    ///
    /// Backed by `_onLevel`, guarded by `lock`: assigned from the main thread
    /// (Task 4's HUD) and read from the realtime audio tap, so both sides
    /// must go through the lock to avoid a data race on the closure reference.
    var onLevel: (([Float]) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onLevel
        }
        set {
            lock.lock()
            _onLevel = newValue
            lock.unlock()
        }
    }
    private var _onLevel: (([Float]) -> Void)?

    /// Hands every converted 16 kHz mono Float32 buffer to a live consumer (the
    /// on-device live transcription preview). Nil when nobody is listening, in
    /// which case the tap does no extra work at all.
    ///
    /// Same contract as `onLevel`: lock-guarded because it is assigned from the
    /// main thread and read from the realtime tap. Unlike `onLevel` it is invoked
    /// synchronously on the audio thread — the consumer must only enqueue, never
    /// block — because buffers must stay in order and hopping to the main thread
    /// per buffer would be pointless overhead.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onBuffer
        }
        set {
            lock.lock()
            _onBuffer = newValue
            lock.unlock()
        }
    }
    private var _onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private static let beamCount = 15
    private static let levelInterval: TimeInterval = 1.0 / 30.0
    private var lastLevelEmit: TimeInterval = 0

    func startRecording() throws {
        lock.lock()
        buffers.removeAll()
        lock.unlock()

        lastLevelEmit = 0

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        // installTap raises an Objective-C exception on an invalid format, which
        // Swift cannot catch — check first and fail as a normal thrown error.
        guard Self.isUsableInputFormat(sampleRate: hardwareFormat.sampleRate,
                                       channelCount: hardwareFormat.channelCount) else {
            throw RecorderError.noInputDevice
        }

        // Target format: 16kHz mono Float32
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Config.sampleRate,
            channels: AVAudioChannelCount(Config.channels),
            interleaved: false
        ) else {
            throw RecorderError.formatError
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: recordingFormat) else {
            throw RecorderError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * recordingFormat.sampleRate / hardwareFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: recordingFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error == nil {
                self.lock.lock()
                self.buffers.append(convertedBuffer)
                self.lock.unlock()

                if let onBuffer = self.onBuffer {
                    onBuffer(convertedBuffer)
                }

                guard let onLevel = self.onLevel else { return }
                let now = CFAbsoluteTimeGetCurrent()
                guard now - self.lastLevelEmit >= Self.levelInterval else { return }
                self.lastLevelEmit = now

                guard let channel = convertedBuffer.floatChannelData?[0] else { return }
                let samples = Array(UnsafeBufferPointer(start: channel,
                                                        count: Int(convertedBuffer.frameLength)))
                let levels = AudioLevelMeter.segmentLevels(samples, segments: Self.beamCount)
                DispatchQueue.main.async { onLevel(levels) }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        isRecording = true
    }

    static func isUsableInputFormat(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate > 0 && channelCount > 0
    }

    func stopRecording() -> StopResult {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        isRecording = false

        lock.lock()
        let captured = buffers
        buffers.removeAll()
        lock.unlock()

        guard !captured.isEmpty else { return .noAudio }

        // Check total duration
        let totalFrames = captured.reduce(0) { $0 + Int($1.frameLength) }
        let duration = Double(totalFrames) / Config.sampleRate
        if duration < Config.minDuration {
            print("Recording too short (\(String(format: "%.1f", duration))s), skipping.")
            return .tooShort(duration)
        }

        // Check audio energy (RMS) to skip silent/background-noise recordings
        var sumOfSquares: Double = 0
        var rmsFrameCount: Int = 0
        for buffer in captured {
            guard let channelData = buffer.floatChannelData?[0] else { continue }
            let frameLength = Int(buffer.frameLength)
            rmsFrameCount += frameLength
            for i in 0..<frameLength {
                let sample = Double(channelData[i])
                sumOfSquares += sample * sample
            }
        }
        let rms = rmsFrameCount > 0 ? sqrt(sumOfSquares / Double(rmsFrameCount)) : 0
        print("Recording RMS energy: \(String(format: "%.4f", rms))")
        if rms < Config.silenceThreshold {
            print("Recording too quiet (RMS \(String(format: "%.4f", rms)) < \(Config.silenceThreshold)), skipping.")
            return .tooQuiet(rms)
        }

        // Write WAV
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phememurmur_recording.wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Config.sampleRate,
            AVNumberOfChannelsKey: Config.channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            let audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
            for buffer in captured {
                try audioFile.write(from: buffer)
            }
            print("Saved recording: \(outputURL.path) (\(String(format: "%.1f", duration))s)")
            return .success(outputURL)
        } catch {
            print("Failed to write WAV: \(error)")
            return .noAudio
        }
    }

    enum StopResult {
        case success(URL)
        case noAudio
        case tooShort(Double)
        case tooQuiet(Double)
    }

    enum RecorderError: LocalizedError {
        case formatError
        case converterError
        case noInputDevice

        var errorDescription: String? {
            switch self {
            case .formatError: return "無法建立錄音格式"
            case .converterError: return "無法轉換麥克風音訊格式"
            case .noInputDevice: return "找不到可用的麥克風"
            }
        }
    }
}
