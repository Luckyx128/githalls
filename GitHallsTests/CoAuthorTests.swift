//
//  CoAuthorTests.swift
//  GitHallsTests
//

import Foundation
import Testing
@testable import GitHalls

struct CoAuthorTests {

    private static let group = "\u{1D}"

    private static func parse(_ values: String...) -> [String] {
        CoAuthorTrailerParser.parse(Substring(values.joined(separator: group)))
    }

    @Test func noTrailersMeansNoCoAuthors() {
        #expect(CoAuthorTrailerParser.parse("").isEmpty)
    }

    @Test func oneCoAuthor() {
        #expect(Self.parse("Ana <ana@x.com>") == ["Ana"])
    }

    @Test func multipleCoAuthorsKeepOrder() {
        #expect(Self.parse("Ana <ana@x.com>", "Bruno <b@x.com>") == ["Ana", "Bruno"])
    }

    @Test func duplicatesCollapse() {
        #expect(Self.parse("Ana <ana@x.com>", "ana <other@x.com>") == ["Ana"])
    }

    @Test func nameWithoutEmailIsKept() {
        #expect(Self.parse("Ana Souza") == ["Ana Souza"])
    }

    @Test func graphParserReadsCoAuthors() {
        let unit = "\u{1F}"
        let fields = ["aaa", "aaa", "", "Ada", "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z", "",
                      "Ana <a@x.com>" + Self.group + "Bruno <b@x.com>", "pair"]
        let commits = CommitGraphParser.parse(fields.joined(separator: unit) + "\u{1E}\n")

        #expect(commits.count == 1)
        #expect(commits[0].coAuthors == ["Ana", "Bruno"])
        #expect(commits[0].compactAuthorsLabel == "Ada +2")
    }

    @Test func logParserReadsCoAuthors() {
        let unit = "\u{1F}"
        let fields = ["aaa", "aaa", "Ada", "2026-01-01T00:00:00Z", "Ana <a@x.com>", "pair"]
        let commits = CommitLogParser.parse(fields.joined(separator: unit) + "\u{1E}\n")

        #expect(commits.count == 1)
        #expect(commits[0].coAuthors == ["Ana"])
        #expect(commits[0].summary == "pair")
    }

    @Test func logParserWithoutTrailers() {
        let unit = "\u{1F}"
        let fields = ["aaa", "aaa", "Ada", "2026-01-01T00:00:00Z", "", "solo"]
        let commits = CommitLogParser.parse(fields.joined(separator: unit) + "\u{1E}\n")

        #expect(commits[0].coAuthors.isEmpty)
        #expect(commits[0].compactAuthorsLabel == "Ada")
    }
}
