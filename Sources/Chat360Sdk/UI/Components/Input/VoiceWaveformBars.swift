import SwiftUI

@available(iOS 13.0, *)
public struct VoiceWaveformBars: View {
    private static let height: CGFloat = 28

    private let amplitudes: [Int]
    private let color: Color
    private let progress: Double?
    private let barCount: Int
    private let barWidth: CGFloat
    private let barGap: CGFloat

    public init(amplitudes: [Int], color: Color, progress: Double? = nil, barCount: Int = 32, barWidth: CGFloat = 3, barGap: CGFloat = 2) {
        self.amplitudes = amplitudes
        self.color = color
        self.progress = progress
        self.barCount = barCount
        self.barWidth = barWidth
        self.barGap = barGap
    }

    private func resampleBars() -> [Double] {
        guard !amplitudes.isEmpty else { return Array(repeating: 0.08, count: barCount) }
        let maxAmp = Double(max(amplitudes.max() ?? 1, 1))
        let bucketSize = max(1, amplitudes.count / barCount)
        return (0..<barCount).map { i in
            let start = min(i * bucketSize, amplitudes.count - 1)
            let end = min(start + bucketSize, amplitudes.count)
            let slice = end > start ? Array(amplitudes[start..<end]) : [amplitudes[start]]
            let avg = Double(slice.reduce(0, +)) / Double(slice.count)
            return max(0.08, avg / maxAmp)
        }
    }

    public var body: some View {
        let bars = resampleBars()
        let playedCount = progress.map { Int($0 * Double(bars.count)) } ?? bars.count
        HStack(alignment: .center, spacing: barGap) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, heightFraction in
                let barHeight = max(barWidth, heightFraction * Self.height)
                let alpha = (progress == nil || index < playedCount) ? 1.0 : 0.35
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color.opacity(alpha))
                    .frame(width: barWidth, height: barHeight)
            }
        }
        .frame(height: Self.height)
        .frame(width: CGFloat(barCount) * (barWidth + barGap))
    }
}
