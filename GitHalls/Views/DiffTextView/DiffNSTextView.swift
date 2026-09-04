//
//  DiffNSTextView.swift
//  GitHalls
//
//  Read-only NSTextView that paints full-width add/deletion tints behind the
//  code and adds diff-specific copy commands to the context menu.
//

import AppKit

@MainActor
protocol DiffTextViewContext: AnyObject {
    var builtDiffText: BuiltDiffText? { get }
    var currentFilePath: String? { get }
}

final class DiffNSTextView: NSTextView {
    weak var diffContext: DiffTextViewContext?
    var diffTheme: DiffTextTheme {
        didSet {
            backgroundColor = diffTheme.viewBackground
            needsDisplay = true
        }
    }

    init(frame: NSRect, textContainer: NSTextContainer, theme: DiffTextTheme) {
        self.diffTheme = theme
        super.init(frame: frame, textContainer: textContainer)
        backgroundColor = theme.viewBackground
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager, let container = textContainer, let built = diffContext?.builtDiffText else { return }

        let painter = DiffGutterPainter(theme: diffTheme, built: built)
        let gutterWidth = built.gutterWidth
        painter.drawColumn(in: rect, gutterWidth: gutterWidth)

        let origin = textContainerOrigin
        let containerRect = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: container)

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, glyphLineRange, _ in
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphLineRange.location)
            guard let info = built.lineInfo(atCharacterIndex: charIndex) else { return }

            let rowRect = NSRect(
                x: 0,
                y: usedRect.minY + origin.y,
                width: self.bounds.width,
                height: usedRect.height
            )

            if let color = self.diffTheme.lineBackground(for: info.kind) {
                color.setFill()
                // Hunk headers read as a full-width band; +/- tints stop at the
                // gutter so the numbers keep their own backdrop.
                let tint = info.kind == .hunkHeader
                    ? rowRect
                    : NSRect(x: gutterWidth, y: rowRect.minY, width: rowRect.width - gutterWidth, height: rowRect.height)
                tint.fill()
            }

            // Only the first fragment of a wrapped line carries its numbers.
            guard charIndex == info.characterRange.location else { return }
            painter.drawRow(info, in: rowRect)
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())

        let copyDiff = NSMenuItem(title: "Copy Entire Diff", action: #selector(copyEntireDiff(_:)), keyEquivalent: "")
        copyDiff.target = self
        menu.addItem(copyDiff)

        let copyPath = NSMenuItem(title: "Copy File Path", action: #selector(copyFilePath(_:)), keyEquivalent: "")
        copyPath.target = self
        menu.addItem(copyPath)

        return menu
    }

    @objc private func copyEntireDiff(_ sender: Any?) {
        guard let text = diffContext?.builtDiffText?.plainText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copyFilePath(_ sender: Any?) {
        guard let path = diffContext?.currentFilePath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copyEntireDiff(_:)):
            return diffContext?.builtDiffText != nil
        case #selector(copyFilePath(_:)):
            return diffContext?.currentFilePath != nil
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}
