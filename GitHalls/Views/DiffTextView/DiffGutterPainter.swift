//
//  DiffGutterPainter.swift
//  GitHalls
//
//  Metrics and drawing for the line-number gutter (old + new columns plus a
//  +/- marker).
//
//  The gutter is painted inside the diff text view, over an indent reserved in
//  every paragraph, instead of living in an NSRulerView: a *visible*
//  NSRulerView leaves the scroll view's document view completely unpainted
//  when the scroll view is hosted through SwiftUI's NSViewRepresentable — the
//  text lays out and `draw(_:)` runs, but nothing the document view draws ever
//  reaches the screen. Drawing it here keeps the numbers out of the selectable
//  text just the same, and the gutter scrolls with the content for free.
//

import AppKit

nonisolated enum DiffGutterMetrics {
    static let horizontalPadding: CGFloat = 6
    static let markerWidth: CGFloat = 12
    static let columnGap: CGFloat = 6
    /// Gap between the gutter's right edge and the first glyph of a line.
    static let textGap: CGFloat = 8

    static func digitWidth(theme: DiffTextTheme) -> CGFloat {
        let sample = NSAttributedString(string: "0", attributes: [.font: theme.headerFont])
        return max(sample.size().width, 6)
    }

    /// Width of one of the two line-number columns.
    static func columnWidth(maxOld: Int, maxNew: Int, theme: DiffTextTheme) -> CGFloat {
        let digits = max(String(max(maxOld, 1)).count, String(max(maxNew, 1)).count)
        return CGFloat(digits) * digitWidth(theme: theme) + 4
    }

    static func gutterWidth(maxOld: Int, maxNew: Int, theme: DiffTextTheme) -> CGFloat {
        let column = columnWidth(maxOld: maxOld, maxNew: maxNew, theme: theme)
        return ceil(horizontalPadding + markerWidth + columnGap + column + columnGap + column + horizontalPadding)
    }
}

/// Draws the gutter column for the rows of an already-laid-out `BuiltDiffText`.
struct DiffGutterPainter {
    let theme: DiffTextTheme
    let built: BuiltDiffText

    private var markerX: CGFloat { DiffGutterMetrics.horizontalPadding }
    private var oldColumnX: CGFloat { markerX + DiffGutterMetrics.markerWidth + DiffGutterMetrics.columnGap }
    private var newColumnX: CGFloat { oldColumnX + built.numberColumnWidth + DiffGutterMetrics.columnGap }

    /// Fills the whole gutter strip plus its separator, before the rows are drawn.
    func drawColumn(in rect: NSRect, gutterWidth: CGFloat) {
        theme.gutterBackground.setFill()
        NSRect(x: 0, y: rect.minY, width: gutterWidth, height: rect.height).fill()

        theme.gutterSeparator.setFill()
        NSRect(x: gutterWidth - 1, y: rect.minY, width: 1, height: rect.height).fill()
    }

    /// Draws the numbers and the +/- marker for one line, in view coordinates.
    func drawRow(_ info: DiffLineLayoutInfo, in rowRect: NSRect) {
        guard info.kind != .hunkHeader else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: theme.headerFont,
            .foregroundColor: theme.gutterText,
        ]
        let column = built.numberColumnWidth

        draw(number: info.oldNumber,
             in: NSRect(x: oldColumnX, y: rowRect.minY, width: column, height: rowRect.height),
             attributes: attributes)
        draw(number: info.newNumber,
             in: NSRect(x: newColumnX, y: rowRect.minY, width: column, height: rowRect.height),
             attributes: attributes)
        draw(marker: info.kind,
             in: NSRect(x: markerX, y: rowRect.minY, width: DiffGutterMetrics.markerWidth, height: rowRect.height))
    }

    private func draw(number: Int?, in rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        guard let number else { return }
        let text = NSAttributedString(string: String(number), attributes: attributes)
        let size = text.size()
        text.draw(in: NSRect(
            x: rect.maxX - size.width,
            y: rect.minY + (rect.height - size.height) / 2,
            width: size.width,
            height: size.height
        ))
    }

    private func draw(marker kind: DiffLine.Kind, in rect: NSRect) {
        let symbol: String
        let color: NSColor
        switch kind {
        case .addition: symbol = "+"; color = theme.additionMarker
        case .deletion: symbol = "\u{2212}"; color = theme.deletionMarker
        default: return
        }
        let text = NSAttributedString(string: symbol, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: color,
        ])
        let size = text.size()
        text.draw(in: NSRect(
            x: rect.minX + (rect.width - size.width) / 2,
            y: rect.minY + (rect.height - size.height) / 2,
            width: size.width,
            height: size.height
        ))
    }
}
