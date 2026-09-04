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

    private var theme: DiffTextTheme {
        DiffTextTheme.make(colorScheme == .dark ? .dark : .light)
    }

    func makeCoordinator() -> DiffTextCoordinator {
        DiffTextCoordinator(highlighter: DiffSyntaxHighlighter.shared)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView(theme: theme)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(diff: diff, theme: theme, presentation: presentation)
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

        self.scrollView = scrollView
        self.textView = textView
        return scrollView
    }

    // MARK: - Content updates

    func update(diff: FileDiff, theme: DiffTextTheme, presentation: DiffPresentation) {
        guard let textView else { return }

        let key = Self.renderKey(diff: diff, theme: theme)
        if key == renderKey, self.theme.identity == theme.identity {
            applyScrollerPolicy(for: presentation)
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
            apply(built)
        case .fill:
            let token = UUID()
            renderToken = token
            Task.detached(priority: .userInitiated) {
                let built = Self.compute(diff: diff, theme: theme, highlighter: highlighter)
                await MainActor.run { [weak self] in
                    guard let self, self.renderToken == token else { return }
                    self.apply(built)
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

    private func apply(_ built: BuiltDiffText) {
        guard let textView else { return }

        builtDiffText = built
        heightCache.removeAll()
        textView.textStorage?.setAttributedString(built.attributedString)

        if let scrollView {
            textView.scroll(NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        textView.invalidateIntrinsicContentSize()
        textView.needsDisplay = true
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
        }
        hasher.combine(theme.identity)
        return "\(diff.path)#\(hasher.finalize())"
    }
}
