import SwiftUI

/// Fallback for any bot node type without a dedicated renderer yet. Only reached when the node
/// has fallback text - `nodeType` is available if a future placeholder is wanted.
struct UnsupportedContent: View {
    var text: String
    var content: BotContent

    var body: some View {
        PlainTextContent(text: text)
    }
}
