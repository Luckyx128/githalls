//
//  CommitMessageComposerTests.swift
//  GitHallsTests
//

import Foundation
import Testing
@testable import GitHalls

struct CommitMessageComposerTests {

    private let ana = CoAuthor(name: "Ana", email: "ana@x.com")
    private let bruno = CoAuthor(name: "Bruno", email: "bruno@x.com")

    @Test func summaryOnlyHasNoBody() {
        let message = CommitMessageComposer.compose(summary: "feat: x", description: "", coAuthors: [])
        #expect(message.summary == "feat: x")
        #expect(message.body == nil)
    }

    @Test func descriptionBecomesBody() {
        let message = CommitMessageComposer.compose(summary: "feat: x", description: "why\nmore", coAuthors: [])
        #expect(message.body == "why\nmore")
    }

    @Test func coAuthorsFollowABlankLine() {
        let message = CommitMessageComposer.compose(summary: "s", description: "body", coAuthors: [ana, bruno])
        #expect(message.body == "body\n\nCo-authored-by: Ana <ana@x.com>\nCo-authored-by: Bruno <bruno@x.com>")
    }

    @Test func coAuthorsWithoutDescription() {
        let message = CommitMessageComposer.compose(summary: "s", description: "  ", coAuthors: [ana])
        #expect(message.body == "Co-authored-by: Ana <ana@x.com>")
    }

    @Test func trailerAlreadyInDescriptionIsNotRepeated() {
        let message = CommitMessageComposer.compose(
            summary: "s",
            description: "body\n\nCo-authored-by: ANA <ANA@x.com>",
            coAuthors: [ana, bruno]
        )
        #expect(message.body == "body\n\nCo-authored-by: ANA <ANA@x.com>\n\nCo-authored-by: Bruno <bruno@x.com>")
    }

    @Test func splitSeparatesSubjectBodyAndTrailers() {
        let parts = CommitMessageComposer.split("feat: x\n\nwhy\n\nCo-authored-by: Ana <ana@x.com>\n")
        #expect(parts.summary == "feat: x")
        #expect(parts.description == "why")
        #expect(parts.coAuthors == [ana])
    }

    @Test func splitSummaryOnly() {
        let parts = CommitMessageComposer.split("fix: y")
        #expect(parts.description.isEmpty)
        #expect(parts.coAuthors.isEmpty)
    }

    @Test func splitDropsRepeatedTrailers() {
        let parts = CommitMessageComposer.split("s\n\nCo-authored-by: Ana <ana@x.com>\nco-authored-by: Ana <ANA@x.com>")
        #expect(parts.coAuthors == [ana])
    }

    @Test func roundTrip() {
        let composed = CommitMessageComposer.compose(summary: "feat: x", description: "line1\n\nline2", coAuthors: [ana, bruno])
        let full = composed.summary + "\n\n" + (composed.body ?? "")
        let parts = CommitMessageComposer.split(full)
        #expect(parts.summary == "feat: x")
        #expect(parts.description == "line1\n\nline2")
        #expect(parts.coAuthors == [ana, bruno])
    }

    @Test func parseValidatesFormat() {
        #expect(CoAuthor.parse(" Ana  <ana@x.com> ") == ana)
        #expect(CoAuthor.parse("Ana") == nil)
        #expect(CoAuthor.parse("<ana@x.com>") == nil)
        #expect(CoAuthor.parse("Ana <ana>") == nil)
        #expect(CoAuthor.parse("Ana <ana@x.com") == nil)
    }

    @Test func uniqueAuthorsKeepsFirstSpelling() {
        let result = CommitMessageComposer.uniqueAuthors(["Ana <ana@x.com>", "Ana S <ANA@x.com>", "bad", "Bruno <bruno@x.com>"])
        #expect(result == [ana, bruno])
    }
}
