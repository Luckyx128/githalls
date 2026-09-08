//
//  JiraADF.swift
//  GitHalls
//

import Foundation

/// Flattens an Atlassian Document Format tree to readable text.
///
/// Jira Cloud v3 returns descriptions as ADF, a JSON tree of nodes, not as
/// text or markup. A detail window wants to read the description, not render
/// a document editor, so this keeps the structure a reader needs — paragraph
/// breaks, list bullets, quotes, code — and drops everything else.
enum JiraADF {
    static func plainText(from document: Any?) -> String {
        guard let node = document as? [String: Any] else { return "" }

        var output = ""
        append(node, to: &output, indent: "")
        return tidy(output)
    }

    // MARK: - Nodes

    private static func append(_ node: [String: Any], to output: inout String, indent: String) {
        switch node["type"] as? String {
        case "text":
            output += node["text"] as? String ?? ""

        case "hardBreak":
            output += "\n" + indent

        case "mention":
            let name = attribute(node, "text")?.trimmingCharacters(in: CharacterSet(charactersIn: "@")) ?? ""
            output += "@" + name

        case "emoji":
            output += attribute(node, "text") ?? attribute(node, "shortName") ?? ""

        case "inlineCard", "blockCard", "embedCard":
            output += attribute(node, "url") ?? ""

        case "date":
            output += formattedDate(attribute(node, "timestamp"))

        case "rule":
            output += indent + "———\n"

        case "paragraph", "heading", "codeBlock", "mediaGroup", "mediaSingle":
            output += indent
            appendChildren(node, to: &output, indent: indent)
            output += "\n"

        case "blockquote":
            appendChildren(node, to: &output, indent: indent + "> ")

        case "panel", "expand", "nestedExpand":
            if let title = attribute(node, "title"), !title.isEmpty {
                output += indent + title + "\n"
            }
            appendChildren(node, to: &output, indent: indent)

        case "bulletList":
            appendList(node, to: &output, indent: indent, ordered: false)

        case "orderedList":
            appendList(node, to: &output, indent: indent, ordered: true)

        case "listItem":
            // The marker was written by the list; the item's paragraphs follow
            // it on the same line, and any nested list goes under it.
            appendListItem(node, to: &output, indent: indent)

        case "table":
            appendTable(node, to: &output, indent: indent)

        case "media":
            output += attribute(node, "alt") ?? "[attachment]"

        default:
            // doc, tableRow, tableCell, taskList, decisionList, and anything
            // Atlassian adds later: the children still read.
            appendChildren(node, to: &output, indent: indent)
        }
    }

    private static func appendChildren(_ node: [String: Any], to output: inout String, indent: String) {
        guard let content = node["content"] as? [[String: Any]] else { return }
        for child in content { append(child, to: &output, indent: indent) }
    }

    private static func appendList(_ node: [String: Any], to output: inout String, indent: String, ordered: Bool) {
        guard let items = node["content"] as? [[String: Any]] else { return }

        for (offset, item) in items.enumerated() {
            output += indent + (ordered ? "\(offset + 1). " : "• ")
            append(item, to: &output, indent: indent + "  ")
        }
    }

    private static func appendListItem(_ node: [String: Any], to output: inout String, indent: String) {
        guard let content = node["content"] as? [[String: Any]] else { return }

        var isFirst = true
        for child in content {
            let type = child["type"] as? String
            let isNestedList = type == "bulletList" || type == "orderedList"

            if isFirst && !isNestedList {
                // The first paragraph shares the marker's line, so it must not
                // re-indent itself.
                appendChildren(child, to: &output, indent: indent)
                output += "\n"
            } else {
                append(child, to: &output, indent: indent)
            }

            isFirst = false
        }

        if isFirst { output += "\n" }
    }

    private static func appendTable(_ node: [String: Any], to output: inout String, indent: String) {
        guard let rows = node["content"] as? [[String: Any]] else { return }

        for row in rows {
            guard let cells = row["content"] as? [[String: Any]] else { continue }

            let texts = cells.map { cell -> String in
                var cellText = ""
                appendChildren(cell, to: &cellText, indent: "")
                return cellText.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
            }

            output += indent + texts.joined(separator: " | ") + "\n"
        }
    }

    // MARK: - Helpers

    private static func attribute(_ node: [String: Any], _ name: String) -> String? {
        guard let attributes = node["attrs"] as? [String: Any], let value = attributes[name] else { return nil }
        return value as? String ?? String(describing: value)
    }

    private static func formattedDate(_ timestamp: String?) -> String {
        guard let timestamp, let millis = Double(timestamp) else { return timestamp ?? "" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: millis / 1000))
    }

    /// Trailing spaces off every line, never more than one blank line in a row,
    /// nothing at the ends.
    private static func tidy(_ text: String) -> String {
        var lines: [String] = []
        var blankRun = 0

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)

            if line.isEmpty {
                blankRun += 1
                if blankRun > 1 || lines.isEmpty { continue }
            } else {
                blankRun = 0
            }

            lines.append(line)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
