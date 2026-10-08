//
//  IssueWorklogParsingTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct IssueWorklogParsingTests {
    @Test func parsesUnits() {
        #expect(IssueWorklogView.seconds(from: "1h 30m") == 5400)
        #expect(IssueWorklogView.seconds(from: "2h") == 7200)
        #expect(IssueWorklogView.seconds(from: "1d") == 28800)
        #expect(IssueWorklogView.seconds(from: "1d2h30m") == 28800 + 7200 + 1800)
    }

    @Test func rejectsNonDurations() {
        #expect(IssueWorklogView.seconds(from: "") == nil)
        #expect(IssueWorklogView.seconds(from: "abc") == nil)
        #expect(IssueWorklogView.seconds(from: "30") == nil)
        #expect(IssueWorklogView.seconds(from: "0m") == nil)
    }
}
