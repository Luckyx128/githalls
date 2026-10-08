//
//  JiraADFBuilder.swift
//  GitHalls
//

import Foundation

extension JiraADF {
    /// Text to ADF for descriptions and comments: markdown where there is any
    /// (headings, quotes, fences, bold / italic / code / links), plain text
    /// otherwise. See `JiraMarkdownADF`.
    static func document(from text: String) -> [String: Any] {
        // Nested lists are the one thing `plainText` writes that the markdown
        // reader has no notion of, and an edit of an existing description must
        // not flatten them. Until it learns nesting, such text takes the plain path.
        let hasNestedList = text.range(of: "(?m)^ +([•*-]|\\d+\\.) ", options: .regularExpression) != nil
        return hasNestedList ? plainDocument(from: text) : JiraMarkdownADF.document(from: text)
    }

    /// The way back from `plainText(from:)`: plain text to an ADF document.
    ///
    /// Blank lines separate paragraphs, a single newline is a line break inside
    /// one. Lines starting `• `, `- ` or `* ` are bullets, `1. ` ordered items
    /// (two spaces of indent nest a level — the same shape `plainText` writes),
    /// and a ``` fence makes a code block. `plainText(from: document(from: t))`
    /// returns `t` for text made of those pieces.
    static func plainDocument(from text: String) -> [String: Any] {
        var blocks: [[String: Any]] = []
        var paragraph: [String] = []
        var items: [ListLine] = []
        var code: [String]?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(["type": "paragraph", "content": inline(paragraph)])
            paragraph = []
        }

        func flushList() {
            var index = 0
            while index < items.count {
                blocks.append(list(items, &index, indent: items[index].indent))
            }
            items = []
        }

        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)

            if code != nil {
                if line.hasPrefix("```") {
                    blocks.append(codeBlock(code ?? []))
                    code = nil
                } else {
                    code?.append(raw)
                }
            } else if line.hasPrefix("```") {
                flushParagraph()
                flushList()
                code = []
            } else if line.isEmpty {
                flushParagraph()
                flushList()
            } else if let item = ListLine(line) {
                flushParagraph()
                items.append(item)
            } else {
                flushList()
                paragraph.append(line)
            }
        }

        // An unclosed fence still keeps what was typed.
        if let code { blocks.append(codeBlock(code)) }
        flushParagraph()
        flushList()

        return ["type": "doc", "version": 1, "content": blocks]
    }

    // MARK: - Pieces

    private struct ListLine {
        let indent: Int
        let ordered: Bool
        let text: String

        init?(_ line: String) {
            let indent = line.prefix { $0 == " " }.count
            let body = String(line.dropFirst(indent))

            if let marker = ["• ", "- ", "* "].first(where: body.hasPrefix) {
                self.init(indent: indent, ordered: false, text: String(body.dropFirst(marker.count)))
            } else if let match = body.range(of: "^\\d+\\. ", options: .regularExpression) {
                self.init(indent: indent, ordered: true, text: String(body[match.upperBound...]))
            } else {
                return nil
            }
        }

        private init(indent: Int, ordered: Bool, text: String) {
            self.indent = indent
            self.ordered = ordered
            self.text = text
        }
    }

    /// One list at `indent`, with deeper lines nested under the item above them.
    private static func list(_ lines: [ListLine], _ index: inout Int, indent: Int) -> [String: Any] {
        let ordered = lines[index].ordered
        var entries: [[String: Any]] = []

        while index < lines.count, lines[index].indent == indent, lines[index].ordered == ordered {
            var content: [[String: Any]] = [["type": "paragraph", "content": inline([lines[index].text])]]
            index += 1

            while index < lines.count, lines[index].indent > indent {
                content.append(list(lines, &index, indent: lines[index].indent))
            }
            entries.append(["type": "listItem", "content": content])
        }

        return ["type": ordered ? "orderedList" : "bulletList", "content": entries]
    }

    private static func codeBlock(_ lines: [String]) -> [String: Any] {
        let body = lines.joined(separator: "\n")
        return ["type": "codeBlock", "content": body.isEmpty ? [] : [["type": "text", "text": body]]]
    }

    /// Text nodes with a hard break between lines; ADF refuses empty text nodes.
    private static func inline(_ lines: [String]) -> [[String: Any]] {
        var nodes: [[String: Any]] = []
        for (offset, line) in lines.enumerated() {
            if offset > 0 { nodes.append(["type": "hardBreak"]) }
            if !line.isEmpty { nodes.append(["type": "text", "text": line]) }
        }
        return nodes
    }
}
