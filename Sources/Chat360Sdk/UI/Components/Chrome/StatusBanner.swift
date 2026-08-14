import SwiftUI

@available(iOS 13.0, *)
public let activeRed = Color(red: 0xE6 / 255, green: 0x33 / 255, blue: 0x12 / 255)

@available(iOS 13.0, *)
public struct StatusBanner: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let text: String
    private let emphasized: Bool

    public init(text: String, emphasized: Bool) {
        self.text = text
        self.emphasized = emphasized
    }

    public var body: some View {
        Text(text)
            .font(typography.textFamily.font(size: 13))
            .foregroundColor(emphasized ? activeRed : colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(colors.backgroundElevated)
    }
}
