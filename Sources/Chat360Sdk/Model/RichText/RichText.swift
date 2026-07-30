import Foundation

/// A parsed, structural representation of the small "chat-safe" HTML subset bot content actually
/// sends (bold/italic/underline/strikethrough, links, line breaks, lists). Deliberately kept free
/// of any SwiftUI type so ``RichTextParser`` is plain-Swift unit-testable; a thin adapter in the UI
/// layer turns this into an `AttributedString` for rendering.
public struct RichText: Equatable {
    public enum Run: Equatable {
        case text(TextRun)
        /// A paragraph/list-item/`<br>` boundary - rendered as a newline.
        case lineBreak
    }

    public struct TextRun: Equatable {
        public var text: String
        public var bold: Bool
        public var italic: Bool
        public var underline: Bool
        public var strikethrough: Bool
        public var linkUrl: String?

        public init(
            text: String,
            bold: Bool = false,
            italic: Bool = false,
            underline: Bool = false,
            strikethrough: Bool = false,
            linkUrl: String? = nil
        ) {
            self.text = text
            self.bold = bold
            self.italic = italic
            self.underline = underline
            self.strikethrough = strikethrough
            self.linkUrl = linkUrl
        }
    }

    public var runs: [Run]

    public init(runs: [Run]) {
        self.runs = runs
    }
}

extension RichText {
    /// Convenience accessor mirroring the Kotlin test helper `RichText.text()`.
    var textRuns: [TextRun] {
        runs.compactMap {
            if case .text(let run) = $0 { return run }
            return nil
        }
    }
}
