import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var buffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    func startRecording() throws {
        lock.lock()
        buffers.removeAll()
        lock.unlock()

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono Float32
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Config.sampleRate,
            channels: AVAudioChannelCount(Config.channels),
            interleaved: false
        ) else {
            throw RecorderError.formatError
        }

        // If hardware format differs, we need a converter
        let needsConversion = hardwareFormat.sampleRate != recordingFormat.sampleRate
            || hardwareFormat.channelCount != recordingFormat.channelCount

        if needsConversion {
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
                }
            }
        } else {
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.lock.lock()
                self.buffers.append(buffer)
                self.lock.unlock()
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stopRecording() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        lock.lock()
        let captured = buffers
        buffers.removeAll()
        lock.unlock()

        guard !captured.isEmpty else { return nil }

        // Check total duration
        let totalFrames = captured.reduce(0) { $0 + Int($1.frameLength) }
        let duration = Double(totalFrames) / Config.sampleRate
        if duration < Config.minDuration {
            print("Recording too short (\(String(format: "%.1f", duration))s), skipping.")
            return nil
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
            return outputURL
        } catch {
            print("Failed to write WAV: \(error)")
            return nil
        }
    }

    enum RecorderError: Error {
        case formatError
        case converterError
    }
}
