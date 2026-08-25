import SwiftUI

@available(iOS 13.0, *)
public let activeRed = Color(red: 0xE6 / 255, green: 0x33 / 255, blue: 0x12 / 255)

@available(iOS 13.0, *)
public struct StatusBanner: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let text: String
    private let emphasized: Bool
    // Only meaningful (and only rendered) alongside `emphasized: true` - the connection-error
    // case. `isSlowConnection`/archived-conversation banners don't pass this, since neither is a
    // broken state to retry out of.
    private let onRetry: (() -> Void)?

    public init(text: String, emphasized: Bool, onRetry: (() -> Void)? = nil) {
        self.text = text
        self.emphasized = emphasized
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(typography.textFamily.font(size: 13))
                .foregroundColor(emphasized ? activeRed : colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if emphasized, let onRetry {
                Button(action: onRetry) {
                    Text("Retry")
                        .font(typography.textFamily.font(size: 13, weight: .semibold))
                        .foregroundColor(activeRed)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(colors.backgroundElevated)
    }
}
