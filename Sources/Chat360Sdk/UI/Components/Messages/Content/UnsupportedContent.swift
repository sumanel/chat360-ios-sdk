import SwiftUI

@available(iOS 15.0, *)
public struct UnsupportedContent: View {
    private let text: String

    public init(text: String, content: BotContent.Unsupported) {
        self.text = text
    }

    public var body: some View {
        PlainTextContent(text)
    }
}
