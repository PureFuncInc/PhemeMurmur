import Foundation

/// Turns a PCM buffer into a fixed number of amplitude values, one per corona
/// beam in the recording HUD. Time-sliced RMS, not a spectrum — enough visual
/// variation without pulling in an FFT.
enum AudioLevelMeter {

    static func segmentLevels(_ samples: [Float], segments: Int) -> [Float] {
        guard segments > 0 else { return [] }
        guard !samples.isEmpty else { return [Float](repeating: 0, count: segments) }

        let chunk = max(1, samples.count / segments)
        return (0..<segments).map { index in
            let start = min(index * chunk, samples.count)
            let end = min(start + chunk, samples.count)
            guard start < end else { return 0 }

            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            let rms = (sum / Float(end - start)).squareRoot()
            return min(max(rms, 0), 1)
        }
    }
}
