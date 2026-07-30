import SwiftUI

/// A curated representative subset stands in for a full bundled emoji dataset - same practical
/// scope as the Android port's own picker, not a byte-for-byte data port.
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

struct EmojiPickerPanel: View {
    var onEmojiSelected: (String) -> Void

    @Environment(\.chat360Colors) private var colors

    private let columns = Array(repeating: GridItem(.flexible()), count: 8)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(smileysAndPeople, id: \.self) { emoji in
                    Button(action: { onEmojiSelected(emoji) }) {
                        Text(emoji).font(.system(size: 22)).padding(6)
                    }
                }
            }
            .padding(8)
        }
        .frame(height: 260)
        .background(colors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
