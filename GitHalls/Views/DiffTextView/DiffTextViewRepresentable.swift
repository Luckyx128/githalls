//
//  DiffTextViewRepresentable.swift
//  GitHalls
//
//  Bridges the AppKit diff renderer into SwiftUI. Two modes:
//  - .fill      : scrolls internally, fills the pane (Changes detail).
//  - .intrinsic : self-sizing, for stacking inside an outer ScrollView
//                 (commit-history file sections).
//

import SwiftUI
import AppKit

enum DiffPresentation: Equatable {
    case fill
    case intrinsic(maxHeight: CGFloat?)
}

struct DiffTextViewRepresentable: NSViewRepresentable {
    let diff: FileDiff
    let presentation: DiffPresentation
    let colorScheme: ColorScheme
    /// Hunk buttons and line selection; nil where the diff is read-only.
    var interaction: DiffInteraction?
    /// Same value for the same file, side and settings: a diff that comes back
    /// under the same key is a refresh and keeps its scroll position.
    var placeIdentity: String?
    /// A click on an expander row: which gap, and which way.
    var onExpand: ((Int, ExpanderRow.Direction) -> Void)?

    // Reading the settings here makes SwiftUI call updateNSView whenever they change.
    @AppStorage(CodeAppearance.lightThemeKey) private var lightThemeName = CodeAppearance.defaultLightTheme
    @AppStorage(CodeAppearance.darkThemeKey) private var darkThemeName = CodeAppearance.defaultDarkTheme
    @AppStorage(CodeAppearance.fontKey) private var fontID = CodeAppearance.defaultFontID
    @AppStorage(CodeAppearance.sizeKey) private var fontSize = CodeAppearance.defaultSize

    private var theme: DiffTextTheme {
        DiffTextTheme.make(CodeAppearance.theme(
            isDark: colorScheme == .dark,
            lightTheme: lightThemeName,
            darkTheme: darkThemeName,
            fontID: fontID,
            size: fontSize
        ))
    }

    func makeCoordinator() -> DiffTextCoordinator {
        DiffTextCoordinator(highlighter: DiffSyntaxHighlighter.shared)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView(theme: theme)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(diff: diff, theme: theme, presentation: presentation,
                                   interaction: interaction, placeIdentity: placeIdentity, onExpand: onExpand)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        switch presentation {
        case .fill:
            return nil
        case .intrinsic(let maxHeight):
            var width = proposal.width ?? nsView.bounds.width
            if !width.isFinite || width < 1 { width = nsView.bounds.width }
            guard width >= 1 else { return nil }
            return context.coordinator.intrinsicSize(forWidth: width, maxHeight: maxHeight)
        }
    }
}

@MainActor
final class DiffTextCoordinator: NSObject, DiffTextViewContext {
    private let highlighter: DiffTextHighlighting

    private weak var scrollView: NSScrollView?
    private var textView: DiffNSTextView?

    private var renderKey: String?
    private var renderToken = UUID()
    private var theme: DiffTextTheme = .make(.light)

    private(set) var builtDiffText: BuiltDiffText?
    private(set) var currentFilePath: String?
    /// The diff `builtDiffText` was made from — not the newest one handed to
    /// `update`, which may still be rendering. Rows and lines match one to one.
    private(set) var currentDiff: FileDiff?
    private(set) var interaction: DiffInteraction?
    private(set) var expandHandler: ((Int, ExpanderRow.Direction) -> Void)?
    private var placeIdentity: String?

    private var heightCache: [String: CGFloat] = [:]

    init(highlighter: DiffTextHighlighting) {
        self.highlighter = highlighter
    }

    // MARK: - View construction

    func makeScrollView(theme: DiffTextTheme) -> NSScrollView {
        self.theme = theme

        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = DiffNSTextView(frame: .zero, textContainer: container, theme: theme)
        textView.diffContext = self
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: 6)

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.viewBackground
        scrollView.documentView = textView
        scrollView.findBarPosition = .aboveContent

        // Content scrolling under a still pointer moves the hovered hunk header.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)

        self.scrollView = scrollView
        self.textView = textView
        return scrollView
    }

    @objc private func clipBoundsChanged() {
        textView?.refreshHover()
    }

    // MARK: - Content updates

    func update(diff: FileDiff, theme: DiffTextTheme, presentation: DiffPresentation,
                interaction: DiffInteraction?, placeIdentity: String? = nil,
                onExpand: ((Int, ExpanderRow.Direction) -> Void)? = nil) {
        guard let textView else { return }
        expandHandler = onExpand

        // The same file and side coming back with new content is a refresh
        // after an action — keep the reader where they were.
        let identity = placeIdentity ?? interaction?.identity
        let keepsPlace = identity != nil && identity == (self.placeIdentity ?? self.interaction?.identity)
        self.placeIdentity = placeIdentity
        let modeChanged = interaction?.mode != self.interaction?.mode || interaction?.side != self.interaction?.side
        self.interaction = interaction
        interaction?.selection.onChange = { [weak textView] in textView?.needsDisplay = true }

        let key = Self.renderKey(diff: diff, theme: theme)
        if key == renderKey, self.theme.identity == theme.identity {
            applyScrollerPolicy(for: presentation)
            if modeChanged {
                textView.window?.invalidateCursorRects(for: textView)
                textView.refreshHover()
            }
            return
        }

        self.theme = theme
        renderKey = key
        currentFilePath = diff.path

        textView.diffTheme = theme
        scrollView?.backgroundColor = theme.viewBackground

        applyScrollerPolicy(for: presentation)

        let highlighter = self.highlighter

        switch presentation {
        case .intrinsic:
            let built = Self.compute(diff: diff, theme: theme, highlighter: highlighter)
            apply(built, diff: diff, keepingPlace: false)
        case .fill:
            let token = UUID()
            renderToken = token
            Task.detached(priority: .userInitiated) {
                let built = Self.compute(diff: diff, theme: theme, highlighter: highlighter)
                await MainActor.run { [weak self] in
                    guard let self, self.renderToken == token else { return }
                    self.apply(built, diff: diff, keepingPlace: keepsPlace)
                }
            }
        }
    }

    private nonisolated static func compute(diff: FileDiff,
                                            theme: DiffTextTheme,
                                            highlighter: DiffTextHighlighting) -> BuiltDiffText {
        let highlighted = DiffHighlightMapper.make(diff, theme: theme.scheme, highlighter: highlighter)
        return DiffAttributedBuilder.build(highlighted, theme: theme)
    }

    private func apply(_ built: BuiltDiffText, diff: FileDiff, keepingPlace: Bool) {
        guard let textView else { return }

        // Read before the text is replaced: afterwards there is nothing to measure.
        let anchor = keepingPlace ? textView.scrollAnchor() : nil

        builtDiffText = built
        currentDiff = diff
        heightCache.removeAll()
        textView.textStorage?.setAttributedString(built.attributedString)

        var restored = false
        if let anchor {
            restored = textView.restore(anchor)
        }
        if restored {
            // A short fade tells the eye the content changed without moving.
            textView.alphaValue = 0.5
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                textView.animator().alphaValue = 1
            }
        } else if let scrollView {
            textView.scroll(NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        textView.invalidateIntrinsicContentSize()
        textView.needsDisplay = true
        textView.window?.invalidateCursorRects(for: textView)
        textView.refreshHover()
    }

    private func applyScrollerPolicy(for presentation: DiffPresentation) {
        // Both modes keep the scroller; in .intrinsic it auto-hides when the
        // content fits the height SwiftUI grants us, and shows past maxHeight.
        scrollView?.hasVerticalScroller = true
    }

    // MARK: - Sizing

    func intrinsicSize(forWidth width: CGFloat, maxHeight: CGFloat?) -> CGSize {
        guard let built = builtDiffText else { return CGSize(width: width, height: 24) }

        let inset = textView?.textContainerInset ?? NSSize(width: 0, height: 6)
        let textWidth = max(width - inset.width * 2, 40)

        let cacheKey = "\(renderKey ?? "-")|\(Int(textWidth.rounded()))"
        let contentHeight: CGFloat
        if let cached = heightCache[cacheKey] {
            contentHeight = cached
        } else {
            contentHeight = Self.measuredHeight(of: built.attributedString, width: textWidth)
            heightCache[cacheKey] = contentHeight
        }

        var height = contentHeight + inset.height * 2 + 2
        if let maxHeight {
            height = min(height, maxHeight)
        }
        return CGSize(width: width, height: max(height, 24))
    }

    /// Lays the text out in a throwaway TextKit stack. Measuring on the live
    /// text view instead reports a zero-height used rect: its container has
    /// `widthTracksTextView` on, so the width we set for the measurement is
    /// not the one the layout ends up using.
    private static func measuredHeight(of attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    // MARK: - Keys

    private static func renderKey(diff: FileDiff, theme: DiffTextTheme) -> String {
        var hasher = Hasher()
        hasher.combine(diff.path)
        hasher.combine(diff.lines.count)
        for line in diff.lines {
            hasher.combine(line.kind)
            hasher.combine(line.text)
            hasher.combine(line.oldLineNumber)
            hasher.combine(line.newLineNumber)
        }
        hasher.combine(theme.identity)
        return "\(diff.path)#\(hasher.finalize())"
    }
}
