import SwiftUI

@available(iOS 16.0, *)
public struct MediaContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    private let message: ChatMessage
    private let content: BotContent.Media
    private let isLiveChat: Bool
    private let onDynamicButtonClick: (String, Int, String?) -> Void

    public init(message: ChatMessage, content: BotContent.Media, isLiveChat: Bool, onDynamicButtonClick: @escaping (String, Int, String?) -> Void = { _, _, _ in }) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onDynamicButtonClick = onDynamicButtonClick
    }

    private var enabled: Bool { message.repliesEnabled && !isLiveChat }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch content.kind {
            case .image:
                AsyncImage(url: URL(string: content.url)) { image in
                    image.resizable().aspectRatio(16.0 / 10.0, contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .clipped()
            case .video, .audio, .other:
                let label = content.kind == .video ? "Play video" : (content.kind == .audio ? "Play audio" : "Open attachment")
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(colors.accent).frame(width: 36, height: 36)
                        Chat360Icon.play.image.foregroundColor(.white).font(.system(size: 14))
                    }
                    Text(content.title ?? label)
                        .font(typography.textFamily.font(size: 14))
                        .foregroundColor(colors.textPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.backgroundSunken)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    if let url = URL(string: content.url) { openURL(url) }
                }
            }
            if let title = content.title, content.kind == .image {
                Spacer().frame(height: 6)
                Text(title).font(typography.textFamily.font(size: 13)).foregroundColor(colors.textSecondary)
            }
            if !message.text.isEmpty {
                Spacer().frame(height: 8)
                PlainTextContent(message.text)
            }
            if !content.dynamicButtons.isEmpty {
                Spacer().frame(height: 10)
                FlowLayout(spacing: 8) {
                    ForEach(Array(content.dynamicButtons.enumerated()), id: \.offset) { i, button in
                        QuickReplyButton(text: button.title, enabled: enabled, selected: false) {
                            onDynamicButtonClick(button.title, -(i + 1), button.componentUuid ?? button.targetId)
                        }
                    }
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
