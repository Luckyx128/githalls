//
//  MarkdownInline.swift
//  GitHalls
//

import Foundation

/// Splits one line into styled runs.
///
/// Left to right, one delimiter at a time: code first, because nothing inside
/// backticks is markup, then links, then emphasis. A delimiter that is never
/// closed is text — a README full of `*` in prose should read as prose, not
/// disappear into an unterminated italic.
enum MarkdownInline {
    static func spans(in line: String) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var plain = ""
        var rest = Substring(line)

        func flushPlain() {
            guard !plain.isEmpty else { return }

            spans.append(MarkdownSpan(plain))
            plain = ""
        }

        while let character = rest.first {
            if character == "`", let closed = take(rest.dropFirst(), until: "`") {
                flushPlain()
                spans.append(MarkdownSpan(String(closed.content), .code))
                rest = closed.remainder
                continue
            }

            if character == "[", let link = takeLink(rest) {
                flushPlain()
                spans.append(MarkdownSpan(link.text, link.style))
                rest = link.remainder
                continue
            }

            if rest.hasPrefix("**"), let closed = take(rest.dropFirst(2), until: "**") {
                flushPlain()
                spans.append(MarkdownSpan(String(closed.content), .bold))
                rest = closed.remainder
                continue
            }

            if character == "*" || character == "_" {
                let delimiter = String(character)
                if let closed = take(rest.dropFirst(), until: delimiter), !closed.content.isEmpty {
                    flushPlain()
                    spans.append(MarkdownSpan(String(closed.content), .italic))
                    rest = closed.remainder
                    continue
                }
            }

            plain.append(character)
            rest = rest.dropFirst()
        }

        flushPlain()
        return spans
    }

    /// Everything up to the next `delimiter`, and what follows it. Nil when it
    /// never closes, which makes the opener ordinary text.
    private static func take(_ text: Substring, until delimiter: String) -> (content: Substring, remainder: Substring)? {
        guard let range = text.range(of: delimiter) else { return nil }

        return (text[text.startIndex..<range.lowerBound], text[range.upperBound...])
    }

    /// `[label](target)`. A target that is not a URL keeps the label as plain
    /// text rather than producing a link that goes nowhere.
    private static func takeLink(_ text: Substring) -> (text: String, style: MarkdownSpan.Style, remainder: Substring)? {
        guard let labelEnd = text.range(of: "](") else { return nil }

        let label = text[text.index(after: text.startIndex)..<labelEnd.lowerBound]
        let afterLabel = text[labelEnd.upperBound...]

        guard let targetEnd = afterLabel.firstIndex(of: ")") else { return nil }

        let target = afterLabel[afterLabel.startIndex..<targetEnd].trimmingCharacters(in: .whitespaces)
        let remainder = afterLabel[afterLabel.index(after: targetEnd)...]

        guard let url = URL(string: target), url.scheme != nil else {
            return (String(label), .plain, remainder)
        }

        return (String(label), .link(url), remainder)
    }
}
