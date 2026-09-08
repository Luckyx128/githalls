//
//  Markdown.swift
//  GitHalls
//

import Foundation

/// A run of text inside a line, and how it should be drawn.
///
/// One style per span rather than a set: nested emphasis is rare in a README,
/// and "***both***" reading as bold is a better trade than a parser nobody can
/// follow.
struct MarkdownSpan: Equatable {
    enum Style: Equatable {
        case plain
        case bold
        case italic
        case code
        case link(URL)
    }

    let text: String
    let style: Style

    init(_ text: String, _ style: Style = .plain) {
        self.text = text
        self.style = style
    }
}

/// One block of a document. Blocks are what a renderer lays out vertically;
/// spans are what it draws inside one.
enum MarkdownBlock: Equatable {
    case heading(level: Int, spans: [MarkdownSpan])
    case paragraph([MarkdownSpan])

    /// `ordered` decides the bullet: a dot or the number the file gave.
    case listItem(spans: [MarkdownSpan], ordered: Bool, marker: String)
    case quote([MarkdownSpan])

    /// Fenced code. Kept verbatim — nothing inside it is markup.
    case code(text: String, language: String?)

    /// A pipe table, row by row, left as written — without the "|---|---|"
    /// separator, which is markup rather than a row.
    ///
    /// Not laid out as a grid: that is two renderers' worth of work for a
    /// block most READMEs use once. Kept together and drawn monospaced, the
    /// columns still line up — which is the part that carries the meaning,
    /// and far better than the wrapped paragraph this used to become.
    case table(rows: [String])

    case rule
}

/// Enough Markdown for a README: headings, paragraphs, lists, quotes, fenced
/// code, rules, and inline emphasis. Deliberately not a full implementation —
/// tables, footnotes and reference links render as the text they are made of,
/// which is worse than nothing only if you expected a browser.
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }

            blocks.append(.paragraph(MarkdownInline.spans(in: paragraph.joined(separator: " "))))
            paragraph = []
        }

        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)[...]

        while let line = lines.first {
            lines = lines.dropFirst()

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // A fence swallows everything up to its closing pair, markup and
            // all — which is the whole point of a code block.
            if let fence = Self.fence(trimmed) {
                flushParagraph()

                var body: [String] = []
                while let next = lines.first {
                    lines = lines.dropFirst()
                    if Self.fence(next.trimmingCharacters(in: .whitespaces)) != nil { break }
                    body.append(next)
                }

                blocks.append(.code(text: body.joined(separator: "\n"), language: fence.isEmpty ? nil : fence))
                continue
            }

            // A pipe line is only a table when the next line is its separator;
            // otherwise it is prose that happens to contain a pipe.
            if trimmed.contains("|"), let separator = lines.first,
               Self.isTableSeparator(separator.trimmingCharacters(in: .whitespaces)) {
                flushParagraph()

                var rows = [trimmed]
                lines = lines.dropFirst()

                while let next = lines.first, next.contains("|") {
                    rows.append(next.trimmingCharacters(in: .whitespaces))
                    lines = lines.dropFirst()
                }

                blocks.append(.table(rows: rows))
                continue
            }

            if Self.isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                continue
            }

            if let heading = Self.heading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, spans: MarkdownInline.spans(in: heading.text)))
                continue
            }

            if let item = Self.listItem(trimmed) {
                flushParagraph()
                blocks.append(.listItem(spans: MarkdownInline.spans(in: item.text),
                                        ordered: item.ordered,
                                        marker: item.marker))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(MarkdownInline.spans(in: body)))
                continue
            }

            paragraph.append(trimmed)
        }

        flushParagraph()
        return blocks
    }

    /// The language after the fence, or nil when the line is not a fence.
    private static func fence(_ line: String) -> String? {
        guard line.hasPrefix("```") || line.hasPrefix("~~~") else { return nil }

        return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    /// "|---|---|" — dashes, colons and pipes, nothing else.
    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("|"), line.contains("-") else { return false }

        return line.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func isRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }

        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" } || stripped.allSatisfy { $0 == "_" }
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }

        let rest = String(line.dropFirst(hashes))
        // "#hashtag" is not a heading; a heading has a space after its hashes.
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }

        return (hashes, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> (text: String, ordered: Bool, marker: String)? {
        for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
            return (String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces), false, "•")
        }

        // "1. ", "12) " — the file's own numbering is kept rather than recounted.
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }

        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }

        return (String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces), true, "\(digits).")
    }
}
