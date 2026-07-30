import Foundation

/// A minimal, permissive single-pass parser for the small HTML subset bot content actually sends
/// (bold/italic/underline/strikethrough, `<a href>` links, `<br>`/`<p>` breaks, `<ul>`/`<ol>`/`<li>`
/// lists). It tracks a real stack of open tags so nesting (`<strong><em>...</em></strong>`) and
/// out-of-order closes (`<b><i>x</b></i>`) resolve the way a lenient HTML parser would, rather than
/// matching tags with a flat regex.
///
/// Deliberately tolerant of malformed input, since it also has to run mid-stream on a
/// chatgpt_message bubble that hasn't finished arriving yet: an unmatched closing tag is ignored,
/// and a tag whose closing ">" hasn't arrived yet (a chunk boundary can land inside a tag) is kept
/// as literal text instead of throwing - the next chunk completes it and it renders correctly then.
public enum RichTextParser {

    private static let boldTags: Set<String> = ["b", "strong"]
    private static let italicTags: Set<String> = ["i", "em"]
    private static let underlineTags: Set<String> = ["u"]
    private static let strikeTags: Set<String> = ["s", "strike", "del"]
    private static let lineBreakTags: Set<String> = ["br", "hr"]
    private static let paragraphTags: Set<String> = ["p", "div", "li"]

    public static func parse(_ html: String) -> RichText {
        let chars = Array(html)
        var runs: [RichText.Run] = []
        var openTags: [String] = []
        var listCounters: [Int] = [] // -1 for a <ul>, >=0 running count for an <ol>
        var linkUrl: String?
        var pendingText = ""

        func flushText() {
            guard !pendingText.isEmpty else { return }
            runs.append(.text(RichText.TextRun(
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
                    pendingText += decoded
                    i += consumed
                    continue
                }
            }
            if c != "<" {
                pendingText.append(c)
                i += 1
                continue
            }

            guard let tagEnd = indexOf(chars, of: ">", from: i) else {
                // Incomplete tag - most likely a chunk boundary mid-stream. Keep it literal for
                // now; once the closing chunk arrives this same call site re-parses the whole
                // merged string and resolves it properly.
                pendingText += String(chars[i...])
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
            let nameEnd = body.firstIndex(where: { $0.isWhitespace }) ?? body.endIndex
            let tagName = String(body[body.startIndex..<nameEnd]).lowercased()
            if tagName.isEmpty { continue } // stray "<>" / "</>"

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
                linkUrl = hrefAttribute(body)
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
                runs.append(.text(RichText.TextRun(text: marker)))
                if !selfClosing { openTags.append(tagName) }
            } else if paragraphTags.contains(tagName) {
                if !runs.isEmpty || !pendingText.isEmpty {
                    flushText()
                    runs.append(.lineBreak)
                }
                if !selfClosing { openTags.append(tagName) }
            } else {
                // A style tag (strong/em/u/...) opening mid-run: flush whatever text came
                // before it under the *old* style first, so only text after this point picks
                // up the new tag's style.
                flushText()
                if !selfClosing { openTags.append(tagName) }
            }
        }
        flushText()
        return RichText(runs: runs)
    }

    private static func indexOf(_ chars: [Character], of target: Character, from: Int) -> Int? {
        var i = from
        while i < chars.count {
            if chars[i] == target { return i }
            i += 1
        }
        return nil
    }

    private static func hrefAttribute(_ body: String) -> String? {
        firstCapturedGroup(pattern: #"href\s*=\s*"([^"]*)""#, in: body)
            ?? firstCapturedGroup(pattern: #"href\s*=\s*'([^']*)'"#, in: body)
    }

    private static func firstCapturedGroup(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
    }

    /// Returns the decoded character(s) and how many source chars they consumed, or nil if `at` isn't a recognized entity.
    private static func decodeEntity(_ chars: [Character], at: Int) -> (String, Int)? {
        guard let end = indexOf(chars, of: ";", from: at), end - at <= 10 else { return nil }
        let entity = String(chars[at...end])
        let decoded: String?
        switch entity {
        case "&amp;": decoded = "&"
        case "&lt;": decoded = "<"
        case "&gt;": decoded = ">"
        case "&quot;": decoded = "\""
        case "&apos;": decoded = "'"
        case "&nbsp;": decoded = " "
        default:
            if entity.hasPrefix("&#x") || entity.hasPrefix("&#X") {
                let hex = String(entity.dropFirst(3).dropLast())
                if !hex.isEmpty, let codePoint = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(codePoint) {
                    decoded = String(Character(scalar))
                } else {
                    decoded = nil
                }
            } else if entity.hasPrefix("&#") {
                let digits = String(entity.dropFirst(2).dropLast())
                if !digits.isEmpty, let codePoint = UInt32(digits), let scalar = Unicode.Scalar(codePoint) {
                    decoded = String(Character(scalar))
                } else {
                    decoded = nil
                }
            } else {
                decoded = nil
            }
        }
        guard let decoded else { return nil }
        return (decoded, end - at + 1)
    }
}
