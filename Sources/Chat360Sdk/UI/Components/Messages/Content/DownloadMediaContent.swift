import SwiftUI

/// Mirrors the DOWNLOAD_MEDIA node: a tappable chip that opens the file (iOS has no
/// app-level download-manager equivalent to Android's `DownloadManager` for arbitrary URLs, so
/// this opens the file's URL - Safari/the system handles the actual download).
struct DownloadMediaContent: View {
    var content: BotContent.DownloadMedia

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: { if let url = URL(string: content.fileUrl) { openURL(url) } }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(colors.accent)
                    Image(systemName: "arrow.down.to.line")
                        .foregroundColor(.white)
                        .font(.system(size: 14))
                }
                .frame(width: 36, height: 36)
                Text(content.fileName)
                    .font(textFont(size: 14))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(12)
            .background(colors.backgroundSunken)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
