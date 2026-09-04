//
//  DiffHighlightMapper.swift
//  GitHalls
//
//  Reconstructs the "old" and "new" side of a FileDiff, highlights each once,
//  then maps every DiffLine back to its highlighted content.
//

import AppKit

nonisolated struct HighlightedDiffLine {
    let kind: DiffLine.Kind
    /// Code content only, no trailing newline, no `+`/`-` prefix.
    let content: NSAttributedString
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let rawText: String
}

nonisolated struct HighlightedDiff {
    let path: String
    let lines: [HighlightedDiffLine]
}

nonisolated enum DiffHighlightMapper {
    static func make(_ diff: FileDiff,
                     theme: DiffTheme,
                     highlighter: DiffTextHighlighting) -> HighlightedDiff {
        let language = diff.languageHint

        let oldRaw = diff.lines.filter { $0.kind == .context || $0.kind == .deletion }.map(\.text)
        let newRaw = diff.lines.filter { $0.kind == .context || $0.kind == .addition }.map(\.text)

        let oldLines = highlight(oldRaw, language: language, theme: theme, highlighter: highlighter)
        let newLines = highlight(newRaw, language: language, theme: theme, highlighter: highlighter)

        var oldIndex = 0
        var newIndex = 0
        var mapped: [HighlightedDiffLine] = []
        mapped.reserveCapacity(diff.lines.count)

        for line in diff.lines {
            switch line.kind {
            case .hunkHeader:
                mapped.append(HighlightedDiffLine(
                    kind: .hunkHeader,
                    content: NSAttributedString(string: line.text),
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    rawText: line.text
                ))
            case .context:
                let content = element(newLines, newIndex) ?? plain(line.text)
                mapped.append(HighlightedDiffLine(
                    kind: .context,
                    content: content,
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: line.newLineNumber,
                    rawText: line.text
                ))
                oldIndex += 1
                newIndex += 1
            case .addition:
                let content = element(newLines, newIndex) ?? plain(line.text)
                mapped.append(HighlightedDiffLine(
                    kind: .addition,
                    content: content,
                    oldLineNumber: nil,
                    newLineNumber: line.newLineNumber,
                    rawText: line.text
                ))
                newIndex += 1
            case .deletion:
                let content = element(oldLines, oldIndex) ?? plain(line.text)
                mapped.append(HighlightedDiffLine(
                    kind: .deletion,
                    content: content,
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: nil,
                    rawText: line.text
                ))
                oldIndex += 1
            }
        }

        return HighlightedDiff(path: diff.path, lines: mapped)
    }

    // MARK: - Helpers

    private static func highlight(_ raw: [String],
                                  language: String?,
                                  theme: DiffTheme,
                                  highlighter: DiffTextHighlighting) -> [NSAttributedString] {
        guard !raw.isEmpty else { return [] }
        let joined = raw.joined(separator: "\n")
        let highlighted = highlighter.highlightedLines(for: joined, language: language, theme: theme)
        guard highlighted.count == raw.count else {
            return raw.map { plain($0) }
        }
        return highlighted
    }

    private static func element(_ lines: [NSAttributedString], _ index: Int) -> NSAttributedString? {
        index >= 0 && index < lines.count ? lines[index] : nil
    }

    private static func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
    }
}
