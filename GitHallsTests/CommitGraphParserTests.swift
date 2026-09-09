//
//  CommitGraphParserTests.swift
//  GitHallsTests
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import Testing
@testable import GitHalls

struct CommitGraphParserTests {

    private static let unit = "\u{1F}"
    private static let record = "\u{1E}"

    /// hash, shortHash, parents, author, authorDate, committerDate, refs, subject
    private static func raw(
        _ hash: String,
        _ shortHash: String,
        _ parents: String,
        _ author: String,
        _ authorDate: String,
        _ committerDate: String,
        _ refs: String,
        _ subject: String
    ) -> String {
        [hash, shortHash, parents, author, authorDate, committerDate, refs, subject]
            .joined(separator: unit) + record + "\n"
    }

    @Test func realRecordRoundTrips() {
        // Captured verbatim from this repository.
        let input = Self.raw(
            "394505fdb234a277d7ed08918ee3e6dad6ecbd93",
            "394505f",
            "7c5512d6fe710dc032705b23b4f2fba2fdb845f3",
            "Lucas Amorim",
            "2026-09-08T18:57:49-03:00",
            "2026-09-08T18:57:49-03:00",
            "HEAD -> refs/heads/main, refs/remotes/origin/main, refs/remotes/origin/HEAD",
            "feat: new wellcome"
        )

        let commits = CommitGraphParser.parse(input)

        #expect(commits.count == 1)
        #expect(commits[0].hash == "394505fdb234a277d7ed08918ee3e6dad6ecbd93")
        #expect(commits[0].shortHash == "394505f")
        #expect(commits[0].authorName == "Lucas Amorim")
        #expect(commits[0].summary == "feat: new wellcome")
        #expect(commits[0].parents == ["7c5512d6fe710dc032705b23b4f2fba2fdb845f3"])
        #expect(commits[0].refs.count == 3)
        #expect(commits[0].isMerge == false)
    }

    /// The field-count trap: an empty %P must still count as a field, or every
    /// root commit — the one place the graph has to stop drawing — is dropped.
    @Test func rootCommitHasNoParents() {
        let input = Self.raw("aaa", "aaa", "", "Ada", "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z", "", "initial")

        let commits = CommitGraphParser.parse(input)

        #expect(commits.count == 1)
        #expect(commits[0].parents.isEmpty)
    }

    @Test func undecoratedCommitStillParses() {
        let input = Self.raw("bbb", "bbb", "aaa", "Ada", "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z", "", "work")

        let commits = CommitGraphParser.parse(input)

        #expect(commits.count == 1)
        #expect(commits[0].refs.isEmpty)
    }

    @Test func multipleParentsKeepGitOrder() {
        let input = Self.raw("ddd", "ddd", "aaa bbb ccc", "Ada", "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z", "", "octopus")

        let commits = CommitGraphParser.parse(input)

        #expect(commits[0].parents == ["aaa", "bbb", "ccc"])
        #expect(commits[0].isMerge)
    }

    /// tformat ends each record with a newline, so the next record's first field
    /// arrives with one glued to the front of the hash.
    @Test func trailingNewlineBetweenRecordsIsTrimmed() {
        let input = Self.raw("aaa", "aaa", "", "Ada", "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z", "", "first")
            + Self.raw("bbb", "bbb", "aaa", "Ada", "2026-01-02T00:00:00Z", "2026-01-02T00:00:00Z", "", "second")

        let commits = CommitGraphParser.parse(input)

        #expect(commits.count == 2)
        #expect(commits[1].hash == "bbb")
        #expect(commits[1].hash.contains("\n") == false)
        #expect(commits[1].parents == ["aaa"])
    }

    @Test func unparseableDateDropsOnlyThatRecord() {
        let input = Self.raw("aaa", "aaa", "", "Ada", "not-a-date", "not-a-date", "", "broken")
            + Self.raw("bbb", "bbb", "", "Ada", "2026-01-02T00:00:00Z", "2026-01-02T00:00:00Z", "", "fine")

        let commits = CommitGraphParser.parse(input)

        #expect(commits.count == 1)
        #expect(commits[0].hash == "bbb")
    }

    @Test func missingCommitterDateFallsBackToAuthorDate() {
        let input = Self.raw("aaa", "aaa", "", "Ada", "2026-01-01T00:00:00Z", "", "", "rebased")

        let commits = CommitGraphParser.parse(input)

        #expect(commits.count == 1)
        #expect(commits[0].committerDate == commits[0].date)
    }

    @Test func wrongFieldCountIsDropped() {
        let input = ["aaa", "aaa", "", "Ada"].joined(separator: Self.unit) + Self.record

        #expect(CommitGraphParser.parse(input).isEmpty)
    }

    @Test func emptyInput() {
        #expect(CommitGraphParser.parse("").isEmpty)
    }
}
