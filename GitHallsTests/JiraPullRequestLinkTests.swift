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

struct JiraPullRequestLinkMarkdownTests {
    @Test func titleBracketsCannotBreakTheComment() {
        let pr = PullRequestSummary(number: 3, title: "[WIP] a](b) *x*", url: "https://github.com/o/r/pull/3")
        let text = JiraPullRequestLink.commentText(for: pr)
        // No markdown link wrapper to unbalance; the URL is its own line.
        #expect(!text.contains("]("))
        #expect(text.hasSuffix("\n" + pr.url))

        let doc = JiraMarkdownADF.document(from: text)
        let plain = JiraADF.plainText(from: doc)
        #expect(plain.contains(pr.url))
    }

    @Test func linkMarkOnlyCommentIsNotMistakenForALink() {
        // The shape an older markdown-link comment reads back as: URL stripped.
        let pr = PullRequestSummary(number: 4, title: "T", url: "https://github.com/o/r/pull/4")
        #expect(!JiraPullRequestLink.isLinked(pr, in: [JiraComment(id: "1", body: "Pull request #4 T")]))
    }
}
