//
//  ContextExpander.swift
//  GitHalls
//
//  Builds what the diff pane shows from the real diff plus the file's own
//  text: the unchanged lines between hunks that the reader asked to see, and
//  the rows that ask for them.
//
//  The result is for display only. The real `FileDiff` is what staging and
//  `PatchBuilder` work from, so nothing here may change it; every row copied
//  from it remembers its place in `sourceIndex`, and the rows added here have
//  none and cannot be selected.
//

import Foundation

/// How much of each stretch of hidden lines has been revealed so far.
/// A stretch is a "gap": 0 is before the first hunk, n is after hunk n-1.
struct ContextExpansion: Equatable {
    struct Gap: Equatable {
        /// Lines revealed under the hunk above.
        var down = 0
        /// Lines revealed over the hunk below.
        var up = 0
    }

    private(set) var gaps: [Int: Gap] = [:]

    var isEmpty: Bool { gaps.isEmpty }

    mutating func reveal(gap: Int, _ direction: ExpanderRow.Direction, step: Int = ContextExpander.step) {
        var state = gaps[gap] ?? Gap()
        switch direction {
        case .down: state.down += step
        case .up: state.up += step
        // Clamped to what is actually hidden when the rows are built.
        case .all: state = Gap(down: Int.max / 4, up: 0)
        }
        gaps[gap] = state
    }
}

enum ContextExpander {
    /// Lines revealed by one click on a "Show N more lines".
    static let step = 20

    /// `source` is the new side of the file, one element per line without its
    /// line ending. Returns `diff` itself when there is nothing to expand, or
    /// when `source` does not match the diff (the file moved on since).
    static func display(diff: FileDiff, source: [String]?, expansion: ContextExpansion) -> FileDiff {
        guard let source, !diff.isBinary, !diff.isNewFile, !diff.isDeletedFile, !diff.isDisplayView,
              diff.hunkCount > 0, matches(diff, source: source)
        else { return diff }

        let hunkCount = diff.hunkCount
        var ranges: [HunkRange?] = Array(repeating: nil, count: hunkCount)
        for line in diff.lines where line.kind == .hunkHeader {
            if let hunk = line.hunkIndex { ranges[hunk] = line.hunkRange }
        }
        guard ranges.allSatisfy({ $0 != nil }) else { return diff }
        let hunks = ranges.compactMap { $0 }

        var out: [DiffLine] = []
        out.reserveCapacity(diff.lines.count)

        func emitGap(_ gap: Int) {
            let isFirst = gap == 0
            let isLast = gap == hunkCount
            let start = isFirst ? 1 : newLast(hunks[gap - 1]) + 1
            let end = isLast ? source.count : newFirst(hunks[gap]) - 1
            let delta = isFirst ? 0 : oldLast(hunks[gap - 1]) - newLast(hunks[gap - 1])
            let hidden = end - start + 1
            guard hidden > 0, end <= source.count else { return }

            let state = expansion.gaps[gap] ?? ContextExpansion.Gap()
            let down = isFirst ? 0 : min(state.down, hidden)
            // "Show all" is recorded as `down`; before the first hunk that means up.
            let up = isLast ? 0 : min(isFirst ? state.up + state.down : state.up, hidden - down)
            let remaining = hidden - down - up

            func context(_ number: Int) -> DiffLine {
                DiffLine(kind: .context, text: source[number - 1], oldLineNumber: number + delta, newLineNumber: number)
            }
            for number in start..<(start + down) { out.append(context(number)) }
            if remaining > 0 {
                out.append(expanderRow(gap: gap, remaining: remaining, isFirst: isFirst, isLast: isLast))
            }
            if up > 0 { for number in (end - up + 1)...end { out.append(context(number)) } }
        }

        for (index, line) in diff.lines.enumerated() {
            if line.kind == .hunkHeader, let hunk = line.hunkIndex { emitGap(hunk) }
            var copy = line
            copy.sourceIndex = index
            out.append(copy)
        }
        emitGap(hunkCount)

        var result = diff
        result.lines = out
        result.isDisplayView = true
        return result
    }

    // MARK: - Geometry

    /// First and last new-side line of a hunk. A hunk with no new-side lines
    /// has `newStart` naming the line *before* it, hence the asymmetry.
    private static func newFirst(_ range: HunkRange) -> Int { range.newCount > 0 ? range.newStart : range.newStart + 1 }
    private static func newLast(_ range: HunkRange) -> Int { range.newCount > 0 ? range.newStart + range.newCount - 1 : range.newStart }
    private static func oldLast(_ range: HunkRange) -> Int { range.oldCount > 0 ? range.oldStart + range.oldCount - 1 : range.oldStart }

    /// The file text agrees with every new-side line the diff itself carries.
    /// Blanks are ignored so a diff made with `-w` still checks out.
    private static func matches(_ diff: FileDiff, source: [String]) -> Bool {
        for line in diff.lines where line.kind == .context || line.kind == .addition {
            guard let number = line.newLineNumber, number >= 1, number <= source.count,
                  stripped(source[number - 1]) == stripped(line.text)
            else { return false }
        }
        return true
    }

    private static func stripped(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) })
    }

    // MARK: - Rows

    private static func expanderRow(gap: Int, remaining: Int, isFirst: Bool, isLast: Bool) -> DiffLine {
        func lines(_ count: Int) -> String { count == 1 ? "1 line" : "\(count) lines" }
        let all = "Show all \(remaining) hidden \(remaining == 1 ? "line" : "lines")"
        let more = "Show \(lines(step)) more"

        var labels: [(String, ExpanderRow.Direction)]
        if isFirst {
            labels = remaining <= step ? [("\u{2191} \(all)", .all)] : [("\u{2191} \(more)", .up), (all, .all)]
        } else if isLast {
            labels = remaining <= step ? [("\u{2193} \(all)", .all)] : [("\u{2193} \(more)", .down), (all, .all)]
        } else {
            labels = remaining <= step
                ? [("\u{2195} \(all)", .all)]
                : [("\u{2193} \(more)", .down), ("\u{2191} \(more)", .up), (all, .all)]
        }

        var text = ""
        var actions: [ExpanderRow.Action] = []
        for (label, direction) in labels {
            if !text.isEmpty { text += "    " }
            let start = text.utf16.count
            text += label
            actions.append(.init(direction: direction, range: start..<text.utf16.count))
        }

        var row = DiffLine(kind: .expander, text: text, oldLineNumber: nil, newLineNumber: nil)
        row.expander = ExpanderRow(gap: gap, actions: actions)
        return row
    }
}

extension FileDiff {
    /// Splits file text into lines the way a diff counts them: on `\n`, with
    /// a trailing `\r` dropped and the last newline not starting a new line.
    static func sourceLines(of text: String) -> [String] {
        DiffParser.splitLines(text).map { piece in
            var line = piece
            if line.unicodeScalars.last == "\r" { line.unicodeScalars.removeLast() }
            return line
        }
    }
}
