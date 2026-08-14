import SwiftUI

@available(iOS 15.0, *)
public struct DownloadMediaContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    private let content: BotContent.DownloadMedia

    public init(content: BotContent.DownloadMedia) {
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(colors.accent).frame(width: 36, height: 36)
                Chat360Icon.download.image.foregroundColor(.white).font(.system(size: 14))
            }
            Text(content.fileName)
                .font(typography.textFamily.font(size: 14))
                .foregroundColor(colors.textPrimary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSunken)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if let url = URL(string: content.fileUrl) { openURL(url) }
        }
    }
}
