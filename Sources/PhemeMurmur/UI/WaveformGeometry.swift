import CoreGraphics

/// Shared geometry for the five-bar waveform used by the app icon, the menu bar
/// template image and the recording HUD. All values are expressed as a fraction
/// of the canvas edge length so a single definition scales to every size.
enum WaveformGeometry {

    enum Detail {
        /// Full artwork: background, glow, star dust, orbital arc.
        case full
        /// Small sizes: background and bars only.
        case minimal
    }

    /// Bar heights as a fraction of the canvas edge, low-mid-high-mid-low.
    static let heightRatios: [CGFloat] = [0.33, 0.66, 1.0, 0.66, 0.33]

    /// Tallest bar occupies this fraction of the canvas edge.
    private static let tallestRatio: CGFloat = 0.54
    private static let barWidthRatio: CGFloat = 0.065
    private static let gapRatio: CGFloat = 0.055

    static func bars(in size: CGFloat) -> [CGRect] {
        let barWidth = size * barWidthRatio
        let gap = size * gapRatio
        let totalWidth = barWidth * CGFloat(heightRatios.count)
            + gap * CGFloat(heightRatios.count - 1)
        let startX = (size - totalWidth) / 2

        return heightRatios.enumerated().map { index, ratio in
            let height = size * tallestRatio * ratio
            let x = startX + CGFloat(index) * (barWidth + gap)
            let y = (size - height) / 2
            return CGRect(x: x, y: y, width: barWidth, height: height)
        }
    }

    static func detail(for size: CGFloat) -> Detail {
        size <= 32 ? .minimal : .full
    }
}
