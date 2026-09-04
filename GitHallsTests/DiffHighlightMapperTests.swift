//
//  DiffHighlightMapperTests.swift
//  GitHallsTests
//

import Foundation
import Testing
@testable import GitHalls

struct DiffHighlightMapperTests {

    /// Returns a deliberately wrong number of lines, to exercise the fallback path.
    private struct BrokenHighlighter: DiffTextHighlighting {
        func highlightedLines(for text: String, language: String?, theme: DiffTheme) -> [NSAttributedString] {
            [NSAttributedString(string: "only one line")]
        }
    }

    private func mapped(_ raw: String, highlighter: DiffTextHighlighting = PlainDiffHighlighter()) -> HighlightedDiff {
        DiffHighlightMapper.make(DiffParser.parse(raw), theme: .light, highlighter: highlighter)
    }

    @Test func oneEntryPerDiffLineWithMatchingKinds() {
        let diff = DiffParser.parse("""
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,3 @@
         unchanged line
        -removed line
        +added line
        """)

        let result = DiffHighlightMapper.make(diff, theme: .light, highlighter: PlainDiffHighlighter())

        #expect(result.lines.count == diff.lines.count)
        for (source, rendered) in zip(diff.lines, result.lines) {
            #expect(source.kind == rendered.kind)
            #expect(source.text == rendered.rawText)
        }
    }

    @Test func preservesLineNumbers() {
        let result = mapped("""
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -12,2 +12,3 @@
         context line
        +added line
        """)

        let context = result.lines.first { $0.kind == .context }
        #expect(context?.oldLineNumber == 12)
        #expect(context?.newLineNumber == 12)

        let addition = result.lines.first { $0.kind == .addition }
        #expect(addition?.newLineNumber == 13)
        #expect(addition?.oldLineNumber == nil)
    }

    @Test func contentMatchesRawTextForEveryCodeLine() {
        let result = mapped("""
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,4 +1,4 @@
         let a = 1
        -let b = 2
        +let b = 3
         let c = 4
        """)

        for line in result.lines where line.kind != .hunkHeader {
            #expect(line.content.string == line.rawText)
        }
    }

    @Test func additionOnlyFileDoesNotCrash() {
        let result = mapped("""
        diff --git a/new.swift b/new.swift
        new file mode 100644
        --- /dev/null
        +++ b/new.swift
        @@ -0,0 +1,2 @@
        +line one
        +line two
        """)

        let additions = result.lines.filter { $0.kind == .addition }
        #expect(additions.count == 2)
        #expect(additions.first?.content.string == "line one")
    }

    @Test func deletionOnlyFileDoesNotCrash() {
        let result = mapped("""
        diff --git a/old.swift b/old.swift
        deleted file mode 100644
        --- a/old.swift
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -line one
        -line two
        """)

        let deletions = result.lines.filter { $0.kind == .deletion }
        #expect(deletions.count == 2)
        #expect(deletions.last?.content.string == "line two")
    }

    @Test func binaryDiffRendersSingleHeader() {
        let result = mapped("""
        diff --git a/image.png b/image.png
        Binary files a/image.png and b/image.png differ
        """)

        #expect(result.lines.count == 1)
        #expect(result.lines.first?.kind == .hunkHeader)
    }

    @Test func fallsBackCleanlyWhenHighlighterMisalignsLineCount() {
        let result = mapped("""
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,3 @@
         unchanged line
        -removed line
        +added line
        """, highlighter: BrokenHighlighter())

        // Still one entry per diff line, still the right raw text.
        let expected = DiffParser.parse("""
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,3 @@
         unchanged line
        -removed line
        +added line
        """)
        #expect(result.lines.count == expected.lines.count)
        for line in result.lines where line.kind != .hunkHeader {
            #expect(line.content.string == line.rawText)
        }
    }
}
