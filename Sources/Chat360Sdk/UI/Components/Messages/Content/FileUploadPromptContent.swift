import SwiftUI

private let fileUploadImageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "tif", "tiff", "bmp", "jfif"]

/// Mirrors the dropzone prompt: a tappable "upload" row inside the bot bubble, plus (when
/// `enableCameraInput` is set and the allowed types include an image extension) a second row to
/// capture a photo directly instead of picking one.
struct FileUploadPromptContent: View {
    var content: BotContent.FileUploadPrompt
    var isLiveChat: Bool
    var onAttachmentClick: () -> Void
    var onCameraClick: () -> Void = {}

    private var showCameraOption: Bool {
        content.allowCamera && content.allowedExtensions.contains { fileUploadImageExtensions.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prompt = content.promptText, !prompt.isEmpty {
                PlainTextContent(text: prompt)
            }
            if showCameraOption {
                UploadRow(systemImage: "camera.fill", label: "Take a photo", enabled: !isLiveChat, onTap: onCameraClick)
            }
            UploadRow(systemImage: "doc.fill", label: "Upload a file", enabled: !isLiveChat, onTap: onAttachmentClick)
        }
    }
}

private struct UploadRow: View {
    var systemImage: String
    var label: String
    var enabled: Bool
    var onTap: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(colors.textPrimary)
                    Image(systemName: systemImage).foregroundColor(.white).font(.system(size: 14))
                }
                .frame(width: 36, height: 36)
                Text(label).font(textFont(size: 14)).foregroundColor(colors.textPrimary)
                Spacer()
            }
            .padding(12)
            .background(colors.backgroundSunken)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
