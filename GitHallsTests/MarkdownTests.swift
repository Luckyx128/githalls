//
//  MarkdownTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct ReadmeFinderTests {
    @Test func findsTheUsualSpellings() {
        #expect(ReadmeFinder.pick(from: ["README.md"]) == "README.md")
        #expect(ReadmeFinder.pick(from: ["readme.markdown"]) == "readme.markdown")
        #expect(ReadmeFinder.pick(from: ["Readme.txt"]) == "Readme.txt")
        #expect(ReadmeFinder.pick(from: ["README"]) == "README")
    }

    @Test func prefersTheMarkdownOneWhenThereAreSeveral() {
        #expect(ReadmeFinder.pick(from: ["README.txt", "README.md"]) == "README.md")
        #expect(ReadmeFinder.pick(from: ["README", "README.rst"]) == "README.rst")
    }

    @Test func ignoresFilesThatMerelyMentionIt() {
        #expect(ReadmeFinder.pick(from: ["READMEME.md", "read-me.md", "docs-readme.md"]) == nil)
    }

    @Test func findsNothingWhenThereIsNothing() {
        #expect(ReadmeFinder.pick(from: []) == nil)
        #expect(ReadmeFinder.pick(from: ["LICENSE", "Package.swift"]) == nil)
    }
}

struct MarkdownParserTests {
    @Test func readsHeadingsByTheirLevel() {
        #expect(MarkdownParser.parse("# One") == [.heading(level: 1, spans: [MarkdownSpan("One")])])
        #expect(MarkdownParser.parse("### Three") == [.heading(level: 3, spans: [MarkdownSpan("Three")])])
    }

    @Test func doesNotTakeAHashtagForAHeading() {
        // No space after the hashes, so it is prose.
        #expect(MarkdownParser.parse("#hashtag") == [.paragraph([MarkdownSpan("#hashtag")])])
    }

    @Test func joinsWrappedLinesIntoOneParagraph() {
        let blocks = MarkdownParser.parse("one\ntwo\n\nthree")

        #expect(blocks == [
            .paragraph([MarkdownSpan("one two")]),
            .paragraph([MarkdownSpan("three")])
        ])
    }

    @Test func keepsFencedCodeVerbatim() {
        let source = """
        ```swift
        let x = **not bold**
        # not a heading
        ```
        """

        #expect(MarkdownParser.parse(source) == [
            .code(text: "let x = **not bold**\n# not a heading", language: "swift")
        ])
    }

    @Test func readsAnUnlabelledFence() {
        #expect(MarkdownParser.parse("```\nplain\n```") == [.code(text: "plain", language: nil)])
    }

    @Test func readsBothKindsOfList() {
        #expect(MarkdownParser.parse("- one") == [.listItem(spans: [MarkdownSpan("one")], ordered: false, marker: "•")])
        #expect(MarkdownParser.parse("2. two") == [.listItem(spans: [MarkdownSpan("two")], ordered: true, marker: "2.")])
    }

    @Test func readsQuotesAndRules() {
        #expect(MarkdownParser.parse("> quoted") == [.quote([MarkdownSpan("quoted")])])
        #expect(MarkdownParser.parse("---") == [.rule])
        #expect(MarkdownParser.parse("***") == [.rule])
    }

    @Test func keepsATableTogetherInsteadOfWrappingItIntoAParagraph() {
        let source = """
        | Project | What |
        |---|---|
        | Core | Logic |
        """

        // The separator line is dropped: it is markup, not a row.
        #expect(MarkdownParser.parse(source) == [
            .table(rows: ["| Project | What |", "| Core | Logic |"])
        ])
    }

    @Test func doesNotTakeAPipeInProseForATable() {
        // No separator line under it, so it is a sentence with a pipe in it.
        let blocks = MarkdownParser.parse("run a | b to pipe")

        #expect(blocks == [.paragraph([MarkdownSpan("run a | b to pipe")])])
    }

    @Test func survivesAnEmptyDocument() {
        #expect(MarkdownParser.parse("").isEmpty)
        #expect(MarkdownParser.parse("\n\n   \n").isEmpty)
    }
}

struct MarkdownInlineTests {
    @Test func readsEmphasisAndCode() {
        #expect(MarkdownInline.spans(in: "a **b** c") == [
            MarkdownSpan("a "), MarkdownSpan("b", .bold), MarkdownSpan(" c")
        ])
        #expect(MarkdownInline.spans(in: "a *b*") == [MarkdownSpan("a "), MarkdownSpan("b", .italic)])
        #expect(MarkdownInline.spans(in: "run `git pull`") == [
            MarkdownSpan("run "), MarkdownSpan("git pull", .code)
        ])
    }

    @Test func treatsBackticksAsLiteralSoMarkupInsideThemSurvives() {
        #expect(MarkdownInline.spans(in: "`**not bold**`") == [MarkdownSpan("**not bold**", .code)])
    }

    @Test func readsALink() {
        let spans = MarkdownInline.spans(in: "see [docs](https://example.com) now")

        #expect(spans.count == 3)
        #expect(spans[1].text == "docs")
        #expect(spans[1].style == .link(URL(string: "https://example.com")!))
    }

    @Test func keepsALinkWithNoRealTargetAsText() {
        #expect(MarkdownInline.spans(in: "[label](#anchor)") == [MarkdownSpan("label")])
    }

    @Test func leavesAnUnclosedDelimiterAsProse() {
        // A lone asterisk in prose must not swallow the rest of the line.
        #expect(MarkdownInline.spans(in: "2 * 3 = 6") == [MarkdownSpan("2 * 3 = 6")])
        #expect(MarkdownInline.spans(in: "a `b") == [MarkdownSpan("a `b")])
    }

    @Test func handlesPlainText() {
        #expect(MarkdownInline.spans(in: "nothing special") == [MarkdownSpan("nothing special")])
        #expect(MarkdownInline.spans(in: "").isEmpty)
    }
}
