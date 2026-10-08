//
//  JiraMarkdownADF.swift
//  GitHalls
//

import Foundation

/// Markdown to Atlassian Document Format, for writing descriptions. Covers what
/// people actually type in a description: headings, paragraphs, bullet and
/// numbered lists, quotes, code fences, and bold / italic / code / links inline.
enum JiraMarkdownADF {
    static func document(from markdown: String) -> [String: Any] {
        ["version": 1, "type": "doc", "content": blocks(from: markdown)]
    }

    // MARK: - Blocks

    private static func blocks(from markdown: String) -> [[String: Any]] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [[String: Any]] = []
        var paragraph: [String] = []
        var index = 0

        func flush() {
            guard !paragraph.isEmpty else { return }
            result.append(["type": "paragraph", "content": inline(paragraph.joined(separator: "\n"))])
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flush()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                var node: [String: Any] = ["type": "codeBlock"]
                if !language.isEmpty { node["attrs"] = ["language": language] }
                if !code.isEmpty { node["content"] = [["type": "text", "text": code.joined(separator: "\n")]] }
                result.append(node)
            } else if trimmed.isEmpty {
                flush()
            } else if let heading = heading(trimmed) {
                flush()
                result.append(heading)
            } else if bulletText(trimmed) != nil || orderedText(trimmed) != nil {
                flush()
                let ordered = orderedText(trimmed) != nil
                var items: [[String: Any]] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let text = ordered ? orderedText(current) : bulletText(current) else { break }
                    items.append(["type": "listItem",
                                  "content": [["type": "paragraph", "content": inline(text)]]])
                    index += 1
                }
                index -= 1
                result.append(["type": ordered ? "orderedList" : "bulletList", "content": items])
            } else if trimmed.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let text = lines[index].trimmingCharacters(in: .whitespaces).dropFirst()
                    quoted.append(text.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                index -= 1
                result.append(["type": "blockquote",
                               "content": [["type": "paragraph", "content": inline(quoted.joined(separator: "\n"))]]])
            } else {
                paragraph.append(trimmed)
            }
            index += 1
        }
        flush()
        return result
    }

    private static func heading(_ line: String) -> [String: Any]? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }

        let text = String(line.dropFirst(hashes + 1))
        return ["type": "heading", "attrs": ["level": hashes], "content": inline(text)]
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private static func orderedText(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return String(rest.dropFirst(2))
    }

    // MARK: - Inline

    private static func inline(_ text: String) -> [[String: Any]] {
        parse(Array(text), marks: [])
    }

    private static func parse(_ chars: [Character], marks: [[String: Any]]) -> [[String: Any]] {
        var nodes: [[String: Any]] = []
        var buffer = ""
        var i = 0

        func emit(_ text: String, _ extra: [[String: Any]] = []) {
            guard !text.isEmpty else { return }
            var node: [String: Any] = ["type": "text", "text": text]
            let all = marks + extra
            if !all.isEmpty { node["marks"] = all }
            nodes.append(node)
        }
        func flush() { emit(buffer); buffer = "" }

        func find(_ delimiter: [Character], from start: Int) -> Int? {
            guard start + delimiter.count <= chars.count else { return nil }
            for j in start...(chars.count - delimiter.count) where Array(chars[j..<j + delimiter.count]) == delimiter {
                return j
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]

            if c == "\\", i + 1 < chars.count, "\\`*_[]()#".contains(chars[i + 1]) {
                // A backslash makes the next punctuation mark literal.
                buffer.append(chars[i + 1])
                i += 2
            } else if c == "\n" {
                flush()
                nodes.append(["type": "hardBreak"])
                i += 1
            } else if c == "`", let end = find(["`"], from: i + 1), end > i + 1 {
                flush()
                emit(String(chars[(i + 1)..<end]), [["type": "code"]])
                i = end + 1
            } else if c == "*", i + 1 < chars.count, chars[i + 1] == "*",
                      let end = find(["*", "*"], from: i + 2), end > i + 2 {
                flush()
                nodes += parse(Array(chars[(i + 2)..<end]), marks: marks + [["type": "strong"]])
                i = end + 2
            } else if c == "*" || (c == "_" && (i == 0 || !chars[i - 1].isLetter && !chars[i - 1].isNumber)),
                      let end = find([c], from: i + 1), end > i + 1,
                      chars[i + 1] != " " {
                flush()
                nodes += parse(Array(chars[(i + 1)..<end]), marks: marks + [["type": "em"]])
                i = end + 1
            } else if c == "[", let close = find(["]", "("], from: i + 1),
                      let end = find([")"], from: close + 2) {
                flush()
                let href = String(chars[(close + 2)..<end])
                nodes += parse(Array(chars[(i + 1)..<close]),
                               marks: marks + [["type": "link", "attrs": ["href": href]]])
                i = end + 1
            } else {
                buffer.append(c)
                i += 1
            }
        }
        flush()
        return nodes
    }
}
