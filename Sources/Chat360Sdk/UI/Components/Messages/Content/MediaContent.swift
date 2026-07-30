import SwiftUI

/// Renders a MEDIA node. Images load inline via `AsyncImage`; video/audio show a play chip that
/// opens the file in the system player - full inline playback (AVPlayer) is a later refinement.
/// `content.dynamicButtons` render as quick-reply pills below, reusing the same
/// `carousel-text-reply` wire path and index convention as `TextCarouselContent`'s own dynamic
/// buttons (see that file's tap handler for the shared -(i+1) encoding).
struct MediaContent: View {
    var message: ChatMessage
    var content: BotContent.Media
    var isLiveChat: Bool
    var onDynamicButtonClick: (_ text: String, _ clickedIndex: Int, _ targetId: String?) -> Void = { _, _, _ in }

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    private var enabled: Bool { message.repliesEnabled && !isLiveChat }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch content.kind {
            case .image:
                AsyncImage(url: URL(string: content.url)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    colors.backgroundSunken
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .clipped()
            case .video, .audio, .other:
                Button(action: { if let url = URL(string: content.url) { openURL(url) } }) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(colors.accent)
                            Image(systemName: "play.fill").foregroundColor(.white).font(.system(size: 14))
                        }
                        .frame(width: 36, height: 36)
                        Text(content.title ?? playLabel)
                            .font(textFont(size: 14))
                            .foregroundColor(colors.textPrimary)
                        Spacer()
                    }
                    .padding(12)
                    .background(colors.backgroundSunken)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if let title = content.title, content.kind == .image {
                Text(title).font(textFont(size: 13)).foregroundColor(colors.textSecondary)
            }
            if !message.text.isEmpty {
                PlainTextContent(text: message.text)
            }
            if !content.dynamicButtons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(content.dynamicButtons.enumerated()), id: \.offset) { i, button in
                            QuickReplyButton(
                                text: button.title,
                                enabled: enabled,
                                selected: false,
                                onTap: { onDynamicButtonClick(button.title, -(i + 1), button.componentUuid ?? button.targetId) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var playLabel: String {
        switch content.kind {
        case .video: return "Play video"
        case .audio: return "Play audio"
        default: return "Open attachment"
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
