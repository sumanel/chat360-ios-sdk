import SwiftUI

@available(iOS 13.0, *)
private let smileysAndPeople = [
    "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇",
    "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚",
    "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🥸",
    "🤩", "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣",
    "😖", "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "😡", "🤬",
    "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰", "😥", "😓", "🤗",
    "🤔", "🤭", "🤫", "🤥", "😶", "😐", "😑", "😬", "🙄", "😯",
    "😦", "😧", "😮", "😲", "😴", "🤤", "😪", "😵", "🤐", "🥴",
    "🤢", "🤮", "🤧", "😷", "🤒", "🤕", "👋", "🤚", "✋", "👌",
    "🤞", "✌️", "🤟", "👍", "👎", "👊", "👏", "🙌", "🙏", "❤️",
]

@available(iOS 14.0, *)
public struct EmojiPickerPanel: View {
    @Environment(\.chat360Colors) private var colors
    private let onEmojiSelected: (String) -> Void
    private let columns = Array(repeating: GridItem(.flexible()), count: 8)

    public init(onEmojiSelected: @escaping (String) -> Void) {
        self.onEmojiSelected = onEmojiSelected
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns) {
                ForEach(smileysAndPeople, id: \.self) { emoji in
                    Text(emoji)
                        .font(.system(size: 22))
                        .padding(6)
                        .onTapGesture { onEmojiSelected(emoji) }
                }
            }
            .padding(8)
        }
        .frame(height: 260)
        .background(colors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
