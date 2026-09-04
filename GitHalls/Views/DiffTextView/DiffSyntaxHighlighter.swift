//
//  DiffSyntaxHighlighter.swift
//  GitHalls
//
//  Syntax highlighting for diff content. Highlights a whole reconstructed
//  file side in one call so multi-line constructs stay correct, then splits
//  the result back into lines.
//

import AppKit
import Highlightr

/// A source of per-line highlighted text. Abstracted so tests can inject a
/// plain (no-JS) implementation.
protocol DiffTextHighlighting: Sendable {
    /// Highlights `text` as `language` and returns one entry per line
    /// (`text.count("\n") + 1` entries). Never throws — falls back to plain
    /// monospaced text on any failure.
    func highlightedLines(for text: String, language: String?, theme: DiffTheme) -> [NSAttributedString]
}

/// Highlightr-backed implementation. All Highlightr (JavaScriptCore) access is
/// confined to `queue`.
final class DiffSyntaxHighlighter: DiffTextHighlighting, @unchecked Sendable {
    static let shared = DiffSyntaxHighlighter()

    /// Skip the JS engine above these sizes — keeps huge generated-file diffs responsive.
    static let maxBytes = 150_000
    static let maxLines = 6_000

    private let queue = DispatchQueue(label: "tech.luckxy.githalls.highlightr")
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let cache = NSCache<NSString, NSAttributedString>()

    private var highlightr: Highlightr?
    private var loadedTheme: DiffTheme?

    private init() {
        cache.countLimit = 96
    }

    func highlightedLines(for text: String, language: String?, theme: DiffTheme) -> [NSAttributedString] {
        let newlineCount = text.reduce(into: 0) { if $1 == "\n" { $0 += 1 } }

        guard let language,
              text.utf16.count <= Self.maxBytes,
              newlineCount < Self.maxLines else {
            return plainLines(text)
        }

        return queue.sync { () -> [NSAttributedString] in
            guard let highlightr = configuredHighlightr(theme: theme) else {
                return plainLines(text)
            }

            let key = "\(theme.highlightrThemeName)|\(language)|\(text.hashValue)" as NSString
            let whole: NSAttributedString
            if let cached = cache.object(forKey: key) {
                whole = cached
            } else if let rendered = highlightr.highlight(text, as: language, fastRender: true) {
                cache.setObject(rendered, forKey: key)
                whole = rendered
            } else {
                return plainLines(text)
            }

            let lines = Self.splitLines(whole)
            // highlight.js can, in rare cases, not round-trip newlines 1:1
            // (HTML entities, stray \r). Bail to plain rather than misalign.
            return lines.count == newlineCount + 1 ? lines : plainLines(text)
        }
    }

    // MARK: - Highlightr lifecycle (queue-confined)

    private func configuredHighlightr(theme: DiffTheme) -> Highlightr? {
        if highlightr == nil {
            highlightr = Highlightr()
        }
        guard let highlightr else { return nil }

        if loadedTheme != theme {
            highlightr.setTheme(to: theme.highlightrThemeName)
            highlightr.theme.setCodeFont(font)
            loadedTheme = theme
            cache.removeAllObjects()
        }
        return highlightr
    }

    // MARK: - Plain fallback

    private func plainLines(_ text: String) -> [NSAttributedString] {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return Self.splitPlain(text).map { NSAttributedString(string: $0, attributes: attributes) }
    }

    // MARK: - Line splitting

    /// Splits an attributed string on "\n", preserving a trailing empty line.
    static func splitLines(_ attributed: NSAttributedString) -> [NSAttributedString] {
        let string = attributed.string as NSString
        var result: [NSAttributedString] = []
        var start = 0
        while true {
            let searchRange = NSRange(location: start, length: string.length - start)
            let newline = string.range(of: "\n", options: [], range: searchRange)
            if newline.location == NSNotFound {
                result.append(attributed.attributedSubstring(from: NSRange(location: start, length: string.length - start)))
                break
            }
            result.append(attributed.attributedSubstring(from: NSRange(location: start, length: newline.location - start)))
            start = newline.location + 1
        }
        return result
    }

    static func splitPlain(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }
}

/// No-JS highlighter: every line is plain monospaced text. Used by tests and as
/// the ultimate fallback.
struct PlainDiffHighlighter: DiffTextHighlighting {
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    func highlightedLines(for text: String, language: String?, theme: DiffTheme) -> [NSAttributedString] {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return text.components(separatedBy: "\n").map { NSAttributedString(string: $0, attributes: attributes) }
    }
}
