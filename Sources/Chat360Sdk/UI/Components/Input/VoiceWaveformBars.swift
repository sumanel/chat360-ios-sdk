import SwiftUI

/// Bucket-resamples `amplitudes` (raw 0-32767 samples) into `barCount` bars and draws them - the
/// live-recording view (progress == nil, every bar drawn at full `color`) and the sent-bubble
/// playback view (progress 0...1, dims unplayed bars) share this one component.
struct VoiceWaveformBars: View {
    var amplitudes: [Int]
    var color: Color
    var progress: Double?
    var barCount: Int = 32
    var barWidth: CGFloat = 3
    var barGap: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let bars = Self.resampleBars(amplitudes, barCount: barCount)
            let totalBarWidth = barWidth + barGap
            let playedCount = progress.map { Int($0 * Double(bars.count)) } ?? bars.count
            for (index, heightFraction) in bars.enumerated() {
                let barHeight = max(barWidth, CGFloat(heightFraction) * size.height)
                let x = CGFloat(index) * totalBarWidth
                let y = (size.height - barHeight) / 2
                let alpha = (progress == nil || index < playedCount) ? 1.0 : 0.35
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(color.opacity(alpha)))
            }
        }
        .frame(width: CGFloat(barCount) * (barWidth + barGap), height: 28)
    }

    private static func resampleBars(_ amplitudes: [Int], barCount: Int) -> [Double] {
        guard !amplitudes.isEmpty else { return Array(repeating: 0.08, count: barCount) }
        let maxAmp = max(amplitudes.max() ?? 1, 1)
        let bucketSize = max(1, amplitudes.count / barCount)
        return (0..<barCount).map { i in
            let start = min(i * bucketSize, amplitudes.count - 1)
            let end = min(start + bucketSize, amplitudes.count)
            let slice = end > start ? amplitudes[start..<end] : [amplitudes[start]]
            let avg = Double(slice.reduce(0, +)) / Double(slice.count)
            return max(0.08, avg / Double(maxAmp))
        }
    }
}
