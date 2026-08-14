import SwiftUI

@available(iOS 15.0, *)
extension String {
    public func toAttributedString(linkColor: Color) -> AttributedString {
        RichTextParser.parse(self).toAttributedString(linkColor: linkColor)
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
