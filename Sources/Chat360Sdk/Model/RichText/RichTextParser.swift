import Foundation

public enum RichTextParser {
    private static let boldTags: Set<String> = ["b", "strong"]
    private static let italicTags: Set<String> = ["i", "em"]
    private static let underlineTags: Set<String> = ["u"]
    private static let strikeTags: Set<String> = ["s", "strike", "del"]
    private static let lineBreakTags: Set<String> = ["br", "hr"]
    private static let paragraphTags: Set<String> = ["p", "div", "li"]
    private static let hrefAttr = try! NSRegularExpression(pattern: "href\\s*=\\s*\"([^\"]*)\"")
    private static let hrefAttrSingleQuoted = try! NSRegularExpression(pattern: "href\\s*=\\s*'([^']*)'")
    private static let decimalEntity = try! NSRegularExpression(pattern: "^&#(\\d+);$")
    private static let hexEntity = try! NSRegularExpression(pattern: "^&#x([0-9a-fA-F]+);$")

    public static func parse(_ html: String) -> RichText {
        let chars = Array(html)
        var runs: [RichText.Run] = []
        var openTags: [String] = []
        var listCounters: [Int] = []
        var linkUrl: String?
        var pendingText = ""

        func flushText() {
            if pendingText.isEmpty { return }
            runs.append(.textRun(RichText.TextRun(
                text: pendingText,
                bold: openTags.contains { boldTags.contains($0) },
                italic: openTags.contains { italicTags.contains($0) },
                underline: openTags.contains { underlineTags.contains($0) },
                strikethrough: openTags.contains { strikeTags.contains($0) },
                linkUrl: linkUrl
            )))
            pendingText = ""
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "&" {
                if let (decoded, consumed) = decodeEntity(chars, at: i) {
                    pendingText.append(decoded)
                    i += consumed
                    continue
                }
            }
            if c != "<" {
                pendingText.append(c)
                i += 1
                continue
            }

            guard let tagEnd = firstIndex(of: ">", in: chars, from: i) else {
                pendingText.append(String(chars[i...]))
                break
            }

            let rawTag = String(chars[(i + 1)..<tagEnd])
            i = tagEnd + 1
            let isClosing = rawTag.hasPrefix("/")
            let selfClosing = rawTag.hasSuffix("/")
            var body = rawTag
            if isClosing { body.removeFirst() }
            if selfClosing { body.removeLast() }
            body = body.trimmingCharacters(in: .whitespaces)
            let nameEnd = body.firstIndex { $0.isWhitespace } ?? body.endIndex
            let tagName = String(body[body.startIndex..<nameEnd]).lowercased()
            if tagName.isEmpty { continue }

            if lineBreakTags.contains(tagName) {
                flushText()
                runs.append(.lineBreak)
            } else if isClosing {
                flushText()
                if let openIndex = openTags.lastIndex(of: tagName) {
                    openTags.removeSubrange(openIndex..<openTags.count)
                }
                if tagName == "a" { linkUrl = nil }
                if tagName == "ul" || tagName == "ol" {
                    if !listCounters.isEmpty { listCounters.removeLast() }
                }
                if paragraphTags.contains(tagName) && !runs.isEmpty { runs.append(.lineBreak) }
            } else if tagName == "a" {
                flushText()
                linkUrl = firstMatchGroup(hrefAttr, in: body) ?? firstMatchGroup(hrefAttrSingleQuoted, in: body)
                if selfClosing { linkUrl = nil } else { openTags.append(tagName) }
            } else if tagName == "ul" {
                if !selfClosing { listCounters.append(-1) }
            } else if tagName == "ol" {
                if !selfClosing { listCounters.append(0) }
            } else if tagName == "li" {
                flushText()
                if !runs.isEmpty { runs.append(.lineBreak) }
                let marker: String
                if !listCounters.isEmpty, listCounters[listCounters.count - 1] >= 0 {
                    listCounters[listCounters.count - 1] += 1
                    marker = "\(listCounters[listCounters.count - 1]). "
                } else {
                    marker = "\u{2022} "
                }
                runs.append(.textRun(RichText.TextRun(text: marker)))
                if !selfClosing { openTags.append(tagName) }
            } else if paragraphTags.contains(tagName) {
                if !runs.isEmpty || !pendingText.isEmpty {
                    flushText()
                    runs.append(.lineBreak)
                }
                if !selfClosing { openTags.append(tagName) }
            } else {
                flushText()
                if !selfClosing { openTags.append(tagName) }
            }
        }
        flushText()
        return RichText(runs: runs)
    }

    private static func firstIndex(of target: Character, in chars: [Character], from: Int) -> Int? {
        var i = from
        while i < chars.count {
            if chars[i] == target { return i }
            i += 1
        }
        return nil
    }

    private static func firstMatchGroup(_ regex: NSRegularExpression, in text: String) -> String? {
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)), match.numberOfRanges > 1 else {
            return nil
        }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else { return nil }
        return nsText.substring(with: range)
    }

    private static func decodeEntity(_ chars: [Character], at: Int) -> (String, Int)? {
        guard let end = firstIndex(of: ";", in: chars, from: at) else { return nil }
        if end - at > 10 { return nil }
        let entity = String(chars[at...end])
        var decoded: String?
        switch entity {
        case "&amp;": decoded = "&"
        case "&lt;": decoded = "<"
        case "&gt;": decoded = ">"
        case "&quot;": decoded = "\""
        case "&apos;": decoded = "'"
        case "&nbsp;": decoded = " "
        default:
            if let codePoint = firstMatchGroup(decimalEntity, in: entity).flatMap({ Int($0) })
                ?? firstMatchGroup(hexEntity, in: entity).flatMap({ Int($0, radix: 16) }),
               let scalar = Unicode.Scalar(codePoint) {
                decoded = String(Character(scalar))
            }
        }
        guard let decoded else { return nil }
        return (decoded, end - at + 1)
    }
}
