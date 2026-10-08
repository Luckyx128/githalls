//
//  JiraPullRequestLinkTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct JiraPullRequestLinkTests {
    private let pr = PullRequestSummary(number: 7, title: "Fix it", url: "https://github.com/o/r/pull/7")

    @Test func commentCarriesNumberTitleAndURL() {
        let text = JiraPullRequestLink.commentText(for: pr)
        #expect(text.contains("#7") && text.contains("Fix it") && text.contains(pr.url))
    }

    @Test func detectsAnExistingLink() {
        let comments = [JiraComment(id: "1", body: JiraPullRequestLink.commentText(for: pr))]
        #expect(JiraPullRequestLink.isLinked(pr, in: comments))
        #expect(!JiraPullRequestLink.isLinked(pr, in: [JiraComment(id: "2", body: "unrelated")]))
    }
}

struct JiraPullRequestLinkPlainTextTests {
    @Test func linkSurvivesAPlainTextRoundTrip() {
        let pr = PullRequestSummary(number: 9, title: "Fix [wip] thing", url: "https://github.com/o/r/pull/9")
        let doc = JiraMarkdownADF.document(from: JiraPullRequestLink.commentText(for: pr))
        let text = JiraADF.plainText(from: doc)
        #expect(JiraPullRequestLink.isLinked(pr, in: [JiraComment(id: "1", body: text)]))
    }
}
