import SwiftUI

@available(iOS 15.0, *)
extension String {
    public func toAttributedString(linkColor: Color) -> AttributedString {
        RichTextParser.parse(self).toAttributedString(linkColor: linkColor)
    }
}

@available(iOS 15.0, *)
extension AttributedString {
    /// Drops newlines from both ends. `RichTextParser` turns a closing `</p>` into a line break, so a
    /// paragraph that ends the markup would otherwise render with an empty line under it.
    func trimmingEdgeNewlines() -> AttributedString {
        var result = self
        while let first = result.characters.first, first.isNewline { result.characters.removeFirst() }
        while let last = result.characters.last, last.isNewline { result.characters.removeLast() }
        return result
    }
}

@available(iOS 15.0, *)
extension RichText {
    fileprivate func toAttributedString(linkColor: Color) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            switch run {
            case .lineBreak:
                result += AttributedString("\n")
            case .textRun(let textRun):
                result += textRun.toAttributedString(linkColor: linkColor)
            }
        }
        return result
    }
}

@available(iOS 15.0, *)
extension RichText.TextRun {
    fileprivate func toAttributedString(linkColor: Color) -> AttributedString {
        var attributed = AttributedString(text)
        if bold && italic {
            attributed.font = .system(size: 15, weight: .bold).italic()
        } else if bold {
            attributed.font = .system(size: 15, weight: .bold)
        } else if italic {
            attributed.font = .system(size: 15).italic()
        }
        if underline { attributed.underlineStyle = .single }
        if strikethrough { attributed.strikethroughStyle = .single }
        if let linkUrl {
            attributed.link = URL(string: linkUrl)
            attributed.foregroundColor = linkColor
        }
        return attributed
    }
}
