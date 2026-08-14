import SwiftUI

@available(iOS 15.0, *)
public struct TypingIndicatorRow: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360UIConfig) private var config

    public init() {}

    public var body: some View {
        HStack(alignment: .center) {
            if config.features.showBotAvatar {
                LogoBadge(size: 28)
                Spacer().frame(width: 8)
            }
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    TypingDot(delayMs: index * 160, color: colors.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(colors.bubbleAiBackground)
            .overlay(Rectangle().stroke(colors.cardBorder, lineWidth: 1))
        }
    }
}

@available(iOS 15.0, *)
private struct TypingDot: View {
    let delayMs: Int
    let color: Color
    @State private var scale: CGFloat = 0.4

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .opacity(0.4 + Double(scale) * 0.6)
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(delayMs) / 1000)
                ) {
                    scale = 1.0
                }
            }
    }
}
