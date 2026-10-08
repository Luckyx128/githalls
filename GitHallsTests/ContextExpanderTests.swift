//
//  ContextExpanderTests.swift
//  GitHallsTests
//
//  Expanded context is display only: these check the rows that appear, their
//  numbers, and that the real diff staging reads is untouched.
//

import Testing
@testable import GitHalls

struct ContextExpanderTests {
    /// A 100-line file whose lines 11 and 61 changed, three lines of context each.
    private let source: [String] = (1...100).map { n in n == 11 || n == 61 ? "new\(n)" : "l\(n)" }

    private var diff: FileDiff {
        DiffParser.parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -8,7 +8,7 @@
         l8
         l9
         l10
        -l11
        +new11
         l12
         l13
         l14
        @@ -58,7 +58,7 @@
         l58
         l59
         l60
        -l61
        +new61
         l62
         l63
         l64

        """)
    }

    private func texts(_ diff: FileDiff, _ kind: DiffLine.Kind) -> [String] {
        diff.lines.filter { $0.kind == kind }.map(\.text)
    }

    @Test func offersExpandersAtBothEndsAndBetweenHunks() {
        let shown = ContextExpander.display(diff: diff, source: source, expansion: ContextExpansion())
        let rows = shown.lines.compactMap(\.expander)
        #expect(rows.map(\.gap) == [0, 1, 2])
        #expect(shown.isDisplayView)
        // 7 lines above, 43 between (15...57), 36 below (65...100).
        let labels = shown.lines.filter { $0.kind == .expander }.map(\.text)
        #expect(labels[0] == "\u{2191} Show all 7 hidden lines")
        #expect(labels[1].contains("Show all 43 hidden lines"))
        #expect(labels[2].hasPrefix("\u{2193} Show 20 lines more") || labels[2].hasPrefix("\u{2193} Show 20 lines"))
    }

    @Test func revealsNumberedContextBelowAndAbove() {
        var expansion = ContextExpansion()
        expansion.reveal(gap: 1, .down)
        expansion.reveal(gap: 1, .up)
        let shown = ContextExpander.display(diff: diff, source: source, expansion: expansion)

        let context = shown.lines.filter { $0.sourceIndex == nil && $0.kind == .context }
        #expect(context.count == 40)
        #expect(context.first?.newLineNumber == 15)
        #expect(context.first?.oldLineNumber == 15)
        #expect(context.last?.newLineNumber == 57)
        #expect(context.first?.text == "l15")
        // The expander now says 3 lines remain (35...37).
        #expect(shown.lines.first { $0.expander?.gap == 1 }?.text == "\u{2195} Show all 3 hidden lines")
    }

    @Test func showAllRemovesTheExpander() {
        var expansion = ContextExpansion()
        expansion.reveal(gap: 0, .all)
        expansion.reveal(gap: 1, .all)
        expansion.reveal(gap: 2, .all)
        let shown = ContextExpander.display(diff: diff, source: source, expansion: expansion)
        #expect(!shown.lines.contains { $0.kind == .expander })
        let numbers = shown.lines.compactMap(\.newLineNumber)
        #expect(numbers == Array(1...100))
    }

    @Test func oldNumbersFollowTheOffsetOfEarlierHunks() {
        // A hunk that adds two lines pushes every later new number two ahead.
        let source = (1...30).map { "l\($0)" }
        let raw = """
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -2,2 +2,4 @@
         l2
        +l3
        +l4
         l5

        """
        let shown = ContextExpander.display(diff: DiffParser.parse(raw), source: source, expansion: {
            var e = ContextExpansion(); e.reveal(gap: 1, .down); return e
        }())
        let revealed = shown.lines.filter { $0.sourceIndex == nil && $0.kind == .context }
        #expect(revealed.first?.newLineNumber == 6)
        #expect(revealed.first?.oldLineNumber == 4)
    }

    @Test func realIndicesAndSelectionSurviveExpansion() {
        let real = diff
        var expansion = ContextExpansion()
        expansion.reveal(gap: 1, .down)
        let shown = ContextExpander.display(diff: real, source: source, expansion: expansion)

        #expect(shown.changedLineIndices(inHunk: 0) == real.changedLineIndices(inHunk: 0))
        #expect(shown.changedLineIndices(inHunk: 1) == real.changedLineIndices(inHunk: 1))

        for (row, line) in shown.lines.enumerated() {
            if let index = shown.realIndex(ofRow: row) {
                #expect(real.lines[index].text == line.text)
                #expect(shown.row(ofRealIndex: index) == row)
            } else {
                #expect(line.kind == .expander || line.kind == .context)
                #expect(!line.isChange)
            }
        }
    }

    @Test func patchesAreBuiltFromTheRealDiffOnly() {
        let real = diff
        let selected = real.changedLineIndices(inHunk: 1)
        let before = PatchBuilder.build(diff: real, selected: selected, direction: .forward)
        var expansion = ContextExpansion()
        expansion.reveal(gap: 1, .all)
        _ = ContextExpander.display(diff: real, source: source, expansion: expansion)
        #expect(PatchBuilder.build(diff: real, selected: selected, direction: .forward) == before)
        #expect(before != nil)
    }

    @Test func staleFileTextIsRefused() {
        var stale = source
        stale[8] = "something else"   // line 9 sits inside the first hunk
        let shown = ContextExpander.display(diff: diff, source: stale, expansion: ContextExpansion())
        #expect(!shown.isDisplayView)
    }

    @Test func newFilesAndMissingSourceAreLeftAlone() {
        let added = DiffParser.syntheticAllAdditions(path: "n.txt", content: "a\nb\n")
        #expect(!ContextExpander.display(diff: added, source: ["a", "b"], expansion: ContextExpansion()).isDisplayView)
        #expect(!ContextExpander.display(diff: diff, source: nil, expansion: ContextExpansion()).isDisplayView)
    }

    @Test func sourceLinesDropLineEndings() {
        #expect(FileDiff.sourceLines(of: "a\r\nb\n") == ["a", "b"])
    }
}
