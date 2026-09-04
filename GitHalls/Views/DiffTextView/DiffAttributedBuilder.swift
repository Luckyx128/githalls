//
//  DiffAttributedBuilder.swift
//  GitHalls
//
//  Turns a HighlightedDiff into the single NSAttributedString rendered by the
//  text view, plus the parallel line table used by the gutter and the
//  background drawer.
//

import AppKit

extension NSAttributedString.Key {
    /// `DiffLine.Kind` for the paragraph — read by the background drawer and gutter.
    static let diffLineKind = NSAttributedString.Key("tech.luckxy.githalls.diffLineKind")
}

nonisolated struct DiffLineLayoutInfo {
    let kind: DiffLine.Kind
    let oldNumber: Int?
    let newNumber: Int?
    /// Range of the whole paragraph (including its trailing "\n") in the storage.
    let characterRange: NSRange
}

/// Immutable render product. A class so it can cross the actor boundary from a
/// background build back to the main actor without copying.
nonisolated final class BuiltDiffText: @unchecked Sendable {
    let attributedString: NSAttributedString
    let lines: [DiffLineLayoutInfo]
    /// Sorted paragraph start offsets, for O(log n) offset → line lookup.
    let paragraphStarts: [Int]
    let plainText: String
    let maxOldNumber: Int
    let maxNewNumber: Int
    /// Indent reserved at the head of every paragraph for the gutter.
    let gutterWidth: CGFloat
    /// Width of one of the gutter's two line-number columns.
    let numberColumnWidth: CGFloat

    init(attributedString: NSAttributedString,
         lines: [DiffLineLayoutInfo],
         paragraphStarts: [Int],
         plainText: String,
         maxOldNumber: Int,
         maxNewNumber: Int,
         gutterWidth: CGFloat,
         numberColumnWidth: CGFloat) {
        self.attributedString = attributedString
        self.lines = lines
        self.paragraphStarts = paragraphStarts
        self.plainText = plainText
        self.maxOldNumber = maxOldNumber
        self.maxNewNumber = maxNewNumber
        self.gutterWidth = gutterWidth
        self.numberColumnWidth = numberColumnWidth
    }

    /// Line info for the paragraph containing `characterIndex`, or nil.
    func lineInfo(atCharacterIndex characterIndex: Int) -> DiffLineLayoutInfo? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = paragraphStarts.count - 1
        var found = 0
        while low <= high {
            let mid = (low + high) / 2
            if paragraphStarts[mid] <= characterIndex {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        let info = lines[found]
        return NSLocationInRange(characterIndex, info.characterRange) || characterIndex == info.characterRange.location
            ? info
            : nil
    }
}

nonisolated enum DiffAttributedBuilder {
    static func build(_ highlighted: HighlightedDiff, theme: DiffTextTheme) -> BuiltDiffText {
        // The gutter is drawn inside the text view, so its width has to be
        // known before the paragraph style that reserves room for it.
        var maxOld = 0
        var maxNew = 0
        for line in highlighted.lines {
            if let old = line.oldLineNumber { maxOld = max(maxOld, old) }
            if let new = line.newLineNumber { maxNew = max(maxNew, new) }
        }
        let numberColumnWidth = DiffGutterMetrics.columnWidth(maxOld: maxOld, maxNew: maxNew, theme: theme)
        let gutterWidth = DiffGutterMetrics.gutterWidth(maxOld: maxOld, maxNew: maxNew, theme: theme)
        let paragraphStyle = makeParagraphStyle(theme: theme, gutterWidth: gutterWidth)

        let output = NSMutableAttributedString()
        var lines: [DiffLineLayoutInfo] = []
        var paragraphStarts: [Int] = []

        for (index, line) in highlighted.lines.enumerated() {
            let paragraphStart = output.length
            paragraphStarts.append(paragraphStart)

            let piece = NSMutableAttributedString(attributedString: line.content)
            // No newline after the last line: it would lay out as an extra
            // empty fragment and pad the bottom of the intrinsic-height views.
            if index < highlighted.lines.count - 1 {
                piece.append(NSAttributedString(string: "\n"))
            }
            let pieceRange = NSRange(location: 0, length: piece.length)

            piece.addAttribute(.paragraphStyle, value: paragraphStyle, range: pieceRange)
            piece.addAttribute(.diffLineKind, value: line.kind, range: pieceRange)

            if line.kind == .hunkHeader {
                piece.addAttribute(.font, value: theme.headerFont, range: pieceRange)
                piece.addAttribute(.foregroundColor, value: theme.hunkHeaderText, range: pieceRange)
            } else {
                fillMissing(.font, in: piece, range: pieceRange, value: theme.font)
                fillMissing(.foregroundColor, in: piece, range: pieceRange, value: theme.baseText)
            }

            output.append(piece)

            lines.append(DiffLineLayoutInfo(
                kind: line.kind,
                oldNumber: line.oldLineNumber,
                newNumber: line.newLineNumber,
                characterRange: NSRange(location: paragraphStart, length: piece.length)
            ))
        }

        return BuiltDiffText(
            attributedString: output,
            lines: lines,
            paragraphStarts: paragraphStarts,
            plainText: output.string,
            maxOldNumber: maxOld,
            maxNewNumber: maxNew,
            gutterWidth: gutterWidth,
            numberColumnWidth: numberColumnWidth
        )
    }

    private static func makeParagraphStyle(theme: DiffTextTheme, gutterWidth: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineHeightMultiple
        style.lineBreakMode = .byCharWrapping
        style.defaultTabInterval = theme.font.maximumAdvancement.width * 4
        style.tabStops = []
        // Room for the gutter, which the text view paints over this indent.
        style.firstLineHeadIndent = gutterWidth + DiffGutterMetrics.textGap
        style.headIndent = gutterWidth + DiffGutterMetrics.textGap
        return style
    }

    /// Adds `value` for `key` to every sub-range of `range` that doesn't
    /// already have it. Collects the missing ranges first — mutating an
    /// NSMutableAttributedString's attribute run table while enumerating it
    /// is unsafe and silently drops most of the fill (e.g. plain identifiers,
    /// whitespace, punctuation Highlightr didn't wrap in a span), which is
    /// exactly the text that then has no `.foregroundColor` at all and
    /// renders as AppKit's default black — invisible against a dark theme.
    private static func fillMissing(_ key: NSAttributedString.Key,
                                    in string: NSMutableAttributedString,
                                    range: NSRange,
                                    value: Any) {
        var missingRanges: [NSRange] = []
        string.enumerateAttribute(key, in: range, options: []) { existing, subRange, _ in
            if existing == nil {
                missingRanges.append(subRange)
            }
        }
        for subRange in missingRanges {
            string.addAttribute(key, value: value, range: subRange)
        }
    }
}
