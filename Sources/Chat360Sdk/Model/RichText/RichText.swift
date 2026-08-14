import Foundation

public struct RichText: Equatable {
    public indirect enum Run: Equatable {
        case textRun(TextRun)
        case lineBreak
    }

    public struct TextRun: Equatable {
        public var text: String
        public var bold: Bool = false
        public var italic: Bool = false
        public var underline: Bool = false
        public var strikethrough: Bool = false
        public var linkUrl: String?

        public init(text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, strikethrough: Bool = false, linkUrl: String? = nil) {
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

extension String {
    public func toPlainText() -> String {
        RichTextParser.parse(self).toPlainText()
    }
}

extension RichText {
    fileprivate func toPlainText() -> String {
        var result = ""
        for run in runs {
            switch run {
            case .lineBreak: result.append("\n")
            case .textRun(let textRun): result.append(textRun.text)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
