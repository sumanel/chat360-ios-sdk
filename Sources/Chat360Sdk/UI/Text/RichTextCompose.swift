import SwiftUI

/// Parses `self` as chat-safe HTML and renders it as a real `AttributedString` (bold/italic/
/// underline/strikethrough spans, clickable links, list bullets) instead of showing literal tags.
extension String {
    func toAttributedString(linkColor: Color) -> AttributedString {
        RichTextParser.parse(self).toAttributedString(linkColor: linkColor)
    }
}

private extension RichText {
    func toAttributedString(linkColor: Color) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            switch run {
            case .lineBreak:
                result += AttributedString("\n")
            case .text(let textRun):
                result += textRun.toAttributedString(linkColor: linkColor)
            }
        }
        return result
    }
}

private extension RichText.TextRun {
    func toAttributedString(linkColor: Color) -> AttributedString {
        var attributed = AttributedString(text)
        var intents: InlinePresentationIntent = []
        if bold { intents.insert(.stronglyEmphasized) }
        if italic { intents.insert(.emphasized) }
        if !intents.isEmpty { attributed.inlinePresentationIntent = intents }
        if underline { attributed.underlineStyle = .single }
        if strikethrough { attributed.strikethroughStyle = .single }
        if let linkUrl, let url = URL(string: linkUrl) {
            attributed.link = url
            attributed.foregroundColor = linkColor
        }
        return attributed
    }
}
