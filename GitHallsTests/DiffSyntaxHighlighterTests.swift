//
//  DiffSyntaxHighlighterTests.swift
//  GitHallsTests
//
//  Exercises the real Highlightr-backed path end to end (JSContext, theme
//  loading, line-count round-trip).
//

import AppKit
import Testing
@testable import GitHalls

@MainActor
struct DiffSyntaxHighlighterTests {

    @Test func returnsOneEntryPerLine() {
        let code = "let a = 1\nlet b = 2\nlet c = 3"
        let lines = DiffSyntaxHighlighter.shared.highlightedLines(for: code, language: "swift", theme: .light)
        #expect(lines.count == 3)
        #expect(lines.map(\.string) == ["let a = 1", "let b = 2", "let c = 3"])
    }

    @Test func appliesColorForKnownLanguage() {
        let code = "func greet() { return \"hi\" }"
        let lines = DiffSyntaxHighlighter.shared.highlightedLines(for: code, language: "swift", theme: .dark)
        #expect(lines.count == 1)

        var sawColor = false
        lines[0].enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: lines[0].length)) { value, _, _ in
            if value != nil { sawColor = true }
        }
        #expect(sawColor)
    }

    @Test func unknownLanguageFallsBackToPlainLines() {
        let code = "one\ntwo"
        let lines = DiffSyntaxHighlighter.shared.highlightedLines(for: code, language: nil, theme: .light)
        #expect(lines.map(\.string) == ["one", "two"])
    }

    @Test func builtDiffTextHasParagraphPerLine() {
        let diff = DiffParser.parse("""
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,3 @@
         let a = 1
        -let b = 2
        +let b = 3
        """)
        let highlighted = DiffHighlightMapper.make(diff, theme: .light, highlighter: DiffSyntaxHighlighter.shared)
        let built = DiffAttributedBuilder.build(highlighted, theme: .make(.light))

        #expect(built.lines.count == diff.lines.count)
        #expect(built.paragraphStarts.count == diff.lines.count)
        // plainText is the code only — no line numbers, no +/- markers.
        #expect(built.plainText.contains("let a = 1"))
        #expect(!built.plainText.contains("@@"))

        // Every paragraph start maps back to its own line.
        for (index, start) in built.paragraphStarts.enumerated() {
            #expect(built.lineInfo(atCharacterIndex: start)?.kind == diff.lines[index].kind)
        }
    }

    /// Regression test: every character of a built diff must end up with an
    /// explicit `.foregroundColor`. Highlightr only wraps the tokens it
    /// recognizes (keywords, strings, numbers, comments…) — plain
    /// identifiers, punctuation and whitespace are left uncoloured and rely
    /// on the builder's `fillMissing` pass. Without an explicit color,
    /// AppKit draws text in black by default, which is invisible against a
    /// dark theme — this caught exactly that bug once already.
    @Test func everyCharacterHasAnExplicitForegroundColor() {
        let diff = DiffParser.parse("""
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,4 +1,4 @@
         let someVeryPlainIdentifier = anotherPlainName + 1
        -let removedPlainThing = 2
        +let addedPlainThing = 3
         return someVeryPlainIdentifier
        """)

        for theme in [DiffTheme.light, .dark] {
            let highlighted = DiffHighlightMapper.make(diff, theme: theme, highlighter: DiffSyntaxHighlighter.shared)
            let built = DiffAttributedBuilder.build(highlighted, theme: .make(theme))

            var uncoloredRanges: [NSRange] = []
            built.attributedString.enumerateAttribute(
                .foregroundColor,
                in: NSRange(location: 0, length: built.attributedString.length)
            ) { value, range, _ in
                if value == nil { uncoloredRanges.append(range) }
            }

            #expect(uncoloredRanges.isEmpty, "uncolored ranges for \(theme): \(uncoloredRanges)")
        }
    }
}
