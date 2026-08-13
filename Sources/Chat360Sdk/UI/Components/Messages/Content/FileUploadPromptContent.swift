import SwiftUI

@available(iOS 15.0, *)
public struct FileUploadPromptContent: View {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "tif", "tiff", "bmp", "jfif"]

    private let content: BotContent.FileUploadPrompt
    private let isLiveChat: Bool
    private let onAttachmentClick: () -> Void
    private let onCameraClick: () -> Void

    public init(content: BotContent.FileUploadPrompt, isLiveChat: Bool, onAttachmentClick: @escaping () -> Void, onCameraClick: @escaping () -> Void = {}) {
        self.content = content
        self.isLiveChat = isLiveChat
        self.onAttachmentClick = onAttachmentClick
        self.onCameraClick = onCameraClick
    }

    private var showCameraOption: Bool {
        content.allowCamera && content.allowedExtensions.contains { Self.imageExtensions.contains($0) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let promptText = content.promptText, !promptText.isEmpty {
                PlainTextContent(promptText)
                Spacer().frame(height: 10)
            }
            if showCameraOption {
                UploadRow(icon: .camera, label: "Take a photo", enabled: !isLiveChat, onClick: onCameraClick)
                Spacer().frame(height: 8)
            }
            UploadRow(icon: .attachFile, label: "Upload a file", enabled: !isLiveChat, onClick: onAttachmentClick)
        }
    }
}

@available(iOS 15.0, *)
private struct UploadRow: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    let icon: Chat360Icon
    let label: String
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(colors.textPrimary).frame(width: 36, height: 36)
                    icon.image.foregroundColor(.white).font(.system(size: 14))
                }
                Text(label)
                    .font(typography.textFamily.font(size: 14))
                    .foregroundColor(colors.textPrimary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.backgroundSunken)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!enabled)
    }
}
