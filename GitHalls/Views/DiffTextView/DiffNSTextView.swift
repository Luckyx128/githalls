//
//  DiffNSTextView.swift
//  GitHalls
//
//  Read-only NSTextView that paints full-width add/deletion tints behind the
//  code, adds diff-specific copy commands to the context menu, and — when the
//  diff has an interaction — handles the partial-staging gestures: hunk
//  buttons on hover, gutter selection and hunk-to-hunk keyboard jumps.
//

import AppKit

@MainActor
protocol DiffTextViewContext: AnyObject {
    var builtDiffText: BuiltDiffText? { get }
    var currentFilePath: String? { get }
    var currentDiff: FileDiff? { get }
    var interaction: DiffInteraction? { get }
    var expandHandler: ((Int, ExpanderRow.Direction) -> Void)? { get }
}

/// The few borderless buttons shown at the trailing edge of a hovered hunk header.
@MainActor
private final class HunkActionBar: NSView {
    private let stack = NSStackView()
    private(set) var hunkHeaderIndex: Int?
    private var actions: [() -> Void] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(hunkHeaderIndex: Int, interaction: DiffInteraction, background: NSColor) {
        self.hunkHeaderIndex = hunkHeaderIndex
        layer?.backgroundColor = background.cgColor
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actions = []

        switch interaction.side {
        case .unstaged:
            add("Stage Hunk", symbol: "plus.circle", destructive: false) { interaction.onStageHunk(hunkHeaderIndex) }
            if interaction.mode == .lines && interaction.canDiscard {
                add("Discard Hunk", symbol: "trash", destructive: true) { interaction.onDiscardHunk(hunkHeaderIndex) }
            }
        case .staged:
            add("Unstage Hunk", symbol: "minus.circle", destructive: false) { interaction.onUnstageHunk(hunkHeaderIndex) }
        }
        layoutSubtreeIfNeeded()
    }

    private func add(_ title: String, symbol: String, destructive: Bool, action: @escaping () -> Void) {
        let button = NSButton(title: title, target: self, action: #selector(fire(_:)))
        button.tag = actions.count
        button.isBordered = false
        button.font = .systemFont(ofSize: 11)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.contentTintColor = destructive ? .systemRed : .secondaryLabelColor
        actions.append(action)
        stack.addArrangedSubview(button)
    }

    @objc private func fire(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
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

    private let actionBar = HunkActionBar()
    private var gutterDrag: (anchor: Int, base: Set<Int>, adds: Bool)?

    private static let jumpMargin: CGFloat = 8

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager, let container = textContainer, let built = diffContext?.builtDiffText else { return }

        let painter = DiffGutterPainter(theme: diffTheme, built: built)
        let gutterWidth = built.gutterWidth
        painter.drawColumn(in: rect, gutterWidth: gutterWidth)

        let origin = textContainerOrigin
        let containerRect = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: container)
        let selection = diffContext?.interaction?.selection.lines
        let displayed = syncedDiff

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
                let tint = info.kind == .hunkHeader || info.kind == .expander
                    ? rowRect
                    : NSRect(x: gutterWidth, y: rowRect.minY, width: rowRect.width - gutterWidth, height: rowRect.height)
                tint.fill()
            }

            if let selection, let real = displayed?.realIndex(ofRow: info.index), selection.contains(real) {
                self.diffTheme.selectionTint.setFill()
                NSRect(x: gutterWidth, y: rowRect.minY, width: rowRect.width - gutterWidth, height: rowRect.height).fill()
                // Solid bar on the gutter's inner edge, so a selected line
                // still reads as one when its tint sits on a +/- tint.
                self.diffTheme.selectionBar.setFill()
                NSRect(x: gutterWidth - 4, y: rowRect.minY, width: 3, height: rowRect.height).fill()
            }

            // Only the first fragment of a wrapped line carries its numbers.
            guard charIndex == info.characterRange.location else { return }
            painter.drawRow(info, in: rowRect)
        }
    }

    // MARK: - Geometry

    /// Full-width rect of a line's paragraph, in view coordinates.
    private func rowRect(forLine index: Int) -> NSRect? {
        guard let layoutManager, let container = textContainer,
              let built = diffContext?.builtDiffText, built.lines.indices.contains(index)
        else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: built.lines[index].characterRange, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        return NSRect(x: 0, y: rect.minY + textContainerOrigin.y, width: bounds.width, height: rect.height)
    }

    /// The diff line under a point. With `clamped`, a point above or below the
    /// text lands on the first or last line instead of nowhere, which is what
    /// a drag past the end of the list wants.
    private func lineIndex(at point: NSPoint, clamped: Bool) -> Int? {
        guard let layoutManager, let container = textContainer, let built = diffContext?.builtDiffText,
              !built.lines.isEmpty, layoutManager.numberOfGlyphs > 0
        else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: max(point.x - origin.x, 0), y: point.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: nil)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        if !clamped, local.y < fragment.minY || local.y > fragment.maxY { return nil }
        let char = layoutManager.characterIndexForGlyph(at: glyph)
        guard let info = built.lineInfo(atCharacterIndex: char) else { return nil }
        return info.index
    }

    /// The diff, only when it lines up row for row with what is on screen — the
    /// text is built off the main thread, so for a moment the two can differ.
    private var syncedDiff: FileDiff? {
        guard let diff = diffContext?.currentDiff, let built = diffContext?.builtDiffText,
              diff.lines.count == built.lines.count else { return nil }
        return diff
    }

    // MARK: - Scroll anchoring

    /// Where the view was looking, in terms that survive the diff being
    /// rebuilt: a source line number plus how far below the viewport top that
    /// line's row starts.
    struct ScrollAnchor {
        let number: Int
        let isNewSide: Bool
        let offset: CGFloat
    }

    func scrollAnchor() -> ScrollAnchor? {
        guard let diff = syncedDiff, let clip = enclosingScrollView?.contentView,
              let first = lineIndex(at: NSPoint(x: 0, y: clip.bounds.minY), clamped: true)
        else { return nil }
        // A header carries no number of its own; the first line under it does.
        guard let index = diff.lines[first...].firstIndex(where: { $0.newLineNumber != nil || $0.oldLineNumber != nil }),
              let rect = rowRect(forLine: index)
        else { return nil }
        let line = diff.lines[index]
        let offset = clip.bounds.minY - rect.minY
        if let number = line.newLineNumber { return ScrollAnchor(number: number, isNewSide: true, offset: offset) }
        return line.oldLineNumber.map { ScrollAnchor(number: $0, isNewSide: false, offset: offset) }
    }

    /// Scrolls so the surviving line nearest the anchor sits where it did.
    /// Returns false when the diff has no numbered line at all.
    @discardableResult
    func restore(_ anchor: ScrollAnchor) -> Bool {
        guard let diff = syncedDiff, let clip = enclosingScrollView?.contentView else { return false }
        var best: (index: Int, distance: Int)?
        for (index, line) in diff.lines.enumerated() {
            guard let number = anchor.isNewSide ? line.newLineNumber : line.oldLineNumber else { continue }
            let distance = abs(number - anchor.number)
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        guard let best, let rect = rowRect(forLine: best.index) else { return false }
        let maxY = max(bounds.height - clip.bounds.height, 0)
        let y = min(max(rect.minY + (best.distance == 0 ? anchor.offset : 0), 0), maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        enclosingScrollView?.reflectScrolledClipView(clip)
        return true
    }

    // MARK: - Hunk buttons

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        refreshHover()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        refreshHover()
    }

    /// Shows the hunk buttons on the header row under the pointer, or hides them.
    /// Also called after a scroll or a new diff: the content moves under a
    /// pointer that did not.
    func refreshHover() {
        guard let interaction = diffContext?.interaction, let diff = syncedDiff, let window else {
            actionBar.removeFromSuperview()
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(point), visibleRect.contains(point),
              let index = lineIndex(at: point, clamped: false),
              diff.lines[index].kind == .hunkHeader, diff.lines[index].hunkIndex != nil,
              let row = rowRect(forLine: index)
        else {
            actionBar.removeFromSuperview()
            return
        }

        guard let realIndex = diff.realIndex(ofRow: index) else {
            actionBar.removeFromSuperview()
            return
        }
        if actionBar.hunkHeaderIndex != realIndex || actionBar.superview == nil {
            actionBar.configure(hunkHeaderIndex: realIndex, interaction: interaction, background: diffTheme.viewBackground)
        }
        if actionBar.superview !== self { addSubview(actionBar) }
        let size = actionBar.fittingSize
        let height = min(size.height, row.height)
        actionBar.frame = NSRect(x: bounds.width - size.width - 8, y: row.midY - height / 2,
                                 width: size.width, height: height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshHover()
    }

    // MARK: - Gutter selection

    override func resetCursorRects() {
        super.resetCursorRects()
        if let built = diffContext?.builtDiffText, diffContext?.expandHandler != nil {
            for info in built.lines where info.kind == .expander {
                if let row = rowRect(forLine: info.index) { addCursorRect(row, cursor: .pointingHand) }
            }
        }
        guard diffContext?.interaction?.mode == .lines, let gutter = diffContext?.builtDiffText?.gutterWidth else { return }
        addCursorRect(NSRect(x: 0, y: visibleRect.minY, width: gutter, height: visibleRect.height), cursor: .pointingHand)
    }

    /// A click on an expander row: the label under the pointer decides what is revealed.
    private func handleExpanderClick(at point: NSPoint) -> Bool {
        guard let handler = diffContext?.expandHandler, let diff = syncedDiff,
              let built = diffContext?.builtDiffText,
              let row = lineIndex(at: point, clamped: false),
              diff.lines[row].kind == .expander, let expander = diff.lines[row].expander,
              !expander.actions.isEmpty
        else { return false }

        let offset = characterIndexForInsertion(at: point) - built.lines[row].characterRange.location
        let action = expander.actions.min { distance(offset, to: $0.range) < distance(offset, to: $1.range) }
        if let action { handler(expander.gap, action.direction) }
        return true
    }

    private func distance(_ offset: Int, to range: Range<Int>) -> Int {
        offset < range.lowerBound ? range.lowerBound - offset : max(offset - range.upperBound, 0)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleExpanderClick(at: point) { return }
        guard let interaction = diffContext?.interaction, interaction.mode == .lines,
              let diff = syncedDiff, let gutter = diffContext?.builtDiffText?.gutterWidth,
              point.x < gutter, let row = lineIndex(at: point, clamped: false)
        else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        let selection = interaction.selection
        let line = diff.lines[row]
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if line.kind == .hunkHeader {
            guard let hunk = line.hunkIndex else { return }
            // Real indices: a selection is keyed on the diff a patch is built from.
            let all = diff.changedLineIndices(inHunk: hunk)
            // A second click on a fully selected hunk lets go of it.
            selection.set(all.isSubset(of: selection.lines) ? selection.lines.subtracting(all) : selection.lines.union(all))
            selection.anchor = all.min()
            return
        }

        let real = diff.realIndex(ofRow: row)
        if flags.contains(.shift), let anchor = selection.anchor, let anchorRow = diff.row(ofRealIndex: anchor) {
            selection.set(selection.lines.union(changedLines(in: diff, between: anchorRow, and: row)))
        } else if flags.contains(.command) {
            guard line.isChange, let real else { return }
            selection.set(selection.lines.symmetricDifference([real]))
            selection.anchor = real
        } else {
            let adds = !(line.isChange && real.map(selection.lines.contains) == true)
            gutterDrag = (row, selection.lines, adds)
            applyDrag(to: row, diff: diff, selection: selection)
            selection.anchor = real
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard gutterDrag != nil, let interaction = diffContext?.interaction, let diff = syncedDiff else {
            super.mouseDragged(with: event)
            return
        }
        autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if let row = lineIndex(at: point, clamped: true) {
            applyDrag(to: row, diff: diff, selection: interaction.selection)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if gutterDrag != nil {
            gutterDrag = nil
        } else {
            super.mouseUp(with: event)
        }
    }

    private func applyDrag(to row: Int, diff: FileDiff, selection: DiffSelection) {
        guard let drag = gutterDrag else { return }
        let range = changedLines(in: diff, between: drag.anchor, and: row)
        selection.set(drag.adds ? drag.base.union(range) : drag.base.subtracting(range))
    }

    private func changedLines(in diff: FileDiff, between a: Int, and b: Int) -> Set<Int> {
        let low = max(min(a, b), 0)
        let high = min(max(a, b), diff.lines.count - 1)
        guard low <= high else { return [] }
        return Set((low...high).filter { diff.lines[$0].isChange }.compactMap { diff.realIndex(ofRow: $0) })
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        switch (event.keyCode, flags) {
        case (125, [.option]): jumpToHunk(forward: true)       // ⌥↓
        case (126, [.option]): jumpToHunk(forward: false)      // ⌥↑
        default:
            if flags.isEmpty, event.charactersIgnoringModifiers == "j" {
                jumpToHunk(forward: true)
            } else if flags.isEmpty, event.charactersIgnoringModifiers == "k" {
                jumpToHunk(forward: false)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// ⌘F opens the text view's own find bar.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "f", window?.firstResponder === self {
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            performFindPanelAction(item)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Esc lets go of the line selection before it does anything else.
    override func cancelOperation(_ sender: Any?) {
        if let selection = diffContext?.interaction?.selection, !selection.lines.isEmpty {
            selection.clear()
        } else {
            super.cancelOperation(sender)
        }
    }

    /// Scrolls the next or previous hunk header to the top, with a small margin.
    private func jumpToHunk(forward: Bool) {
        guard let built = diffContext?.builtDiffText, let clip = enclosingScrollView?.contentView else { return }
        let top = clip.bounds.minY + Self.jumpMargin
        let headers = built.lines.indices.filter { built.lines[$0].kind == .hunkHeader }
        let ys = headers.compactMap { rowRect(forLine: $0)?.minY }

        let target: CGFloat?
        if forward {
            target = ys.first { $0 > top + 2 }
        } else {
            target = ys.last { $0 < top - 2 } ?? (clip.bounds.minY > 0 ? Self.jumpMargin : nil)
        }
        guard let target else { return }

        let maxY = max(bounds.height - clip.bounds.height, 0)
        let origin = NSPoint(x: clip.bounds.minX, y: min(max(target - Self.jumpMargin, 0), maxY))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            clip.animator().setBoundsOrigin(origin)
        }
        enclosingScrollView?.reflectScrolledClipView(clip)
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
