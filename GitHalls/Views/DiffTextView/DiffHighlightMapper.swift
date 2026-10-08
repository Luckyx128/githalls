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
    /// UTF-16 ranges of `content` holding the words that changed inside a
    /// paired +/- line; the builder tints them.
    var wordRanges: [Range<Int>] = []
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

        let wordRanges = Self.wordRanges(for: diff)

        for (lineIndex, line) in diff.lines.enumerated() {
            switch line.kind {
            case .hunkHeader, .expander:
                mapped.append(HighlightedDiffLine(
                    kind: line.kind,
                    content: NSAttributedString(string: line.text),
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    rawText: line.text
                ))
            case .context:
                let content = element(newLines, newIndex) ?? plain(line.text, theme)
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
                let content = element(newLines, newIndex) ?? plain(line.text, theme)
                mapped.append(HighlightedDiffLine(
                    kind: .addition,
                    content: content,
                    oldLineNumber: nil,
                    newLineNumber: line.newLineNumber,
                    rawText: line.text,
                    wordRanges: wordRanges[lineIndex] ?? []
                ))
                newIndex += 1
            case .deletion:
                let content = element(oldLines, oldIndex) ?? plain(line.text, theme)
                mapped.append(HighlightedDiffLine(
                    kind: .deletion,
                    content: content,
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: nil,
                    rawText: line.text,
                    wordRanges: wordRanges[lineIndex] ?? []
                ))
                oldIndex += 1
            }
        }

        return HighlightedDiff(path: diff.path, lines: mapped)
    }

    // MARK: - Helpers

    /// Past this many lines the word comparison is skipped altogether: a diff
    /// that big is being skimmed, not read word by word.
    static let wordDiffLineLimit = 6000

    /// Changed words per line index, hunk by hunk, so a run of deletions is
    /// never paired with additions from the next hunk.
    private static func wordRanges(for diff: FileDiff) -> [Int: [Range<Int>]] {
        guard diff.lines.count <= wordDiffLineLimit else { return [:] }
        var result: [Int: [Range<Int>]] = [:]
        var start = 0
        while start < diff.lines.count {
            var end = start
            let hunk = diff.lines[start].hunkIndex
            while end < diff.lines.count, diff.lines[end].hunkIndex == hunk { end += 1 }
            if hunk != nil {
                let slice = diff.lines[start..<end]
                let pairs = WordDiff.pairs(kinds: slice.map(\.kind), texts: slice.map(\.text))
                for (offset, ranges) in pairs { result[start + offset] = ranges }
            }
            start = end
        }
        return result
    }

    private static func highlight(_ raw: [String],
                                  language: String?,
                                  theme: DiffTheme,
                                  highlighter: DiffTextHighlighting) -> [NSAttributedString] {
        guard !raw.isEmpty else { return [] }
        let joined = raw.joined(separator: "\n")
        let highlighted = highlighter.highlightedLines(for: joined, language: language, theme: theme)
        guard highlighted.count == raw.count else {
            return raw.map { plain($0, theme) }
        }
        return highlighted
    }

    private static func element(_ lines: [NSAttributedString], _ index: Int) -> NSAttributedString? {
        index >= 0 && index < lines.count ? lines[index] : nil
    }

    private static func plain(_ text: String, _ theme: DiffTheme) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: theme.font])
    }
}
