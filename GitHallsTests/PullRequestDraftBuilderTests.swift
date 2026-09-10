//
//  PullRequestDraftBuilderTests.swift
//  GitHallsTests
//
//  Created by Lucas de Amorim on 10/09/26.
//

import Foundation
import Testing
@testable import GitHalls

struct PullRequestDraftBuilderTests {

    private func commit(_ summary: String, hash: String = "abc1234") -> Commit {
        Commit(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            authorName: "Lucas",
            date: Date(timeIntervalSince1970: 0),
            summary: summary
        )
    }

    @Test func singleCommitLendsItsMessage() {
        let draft = PullRequestDraftBuilder.draft(
            branch: "feat/inline-diff",
            commits: [commit("feat: inline diff")],
            singleCommitMessage: "feat: inline diff\n\nOpens the diff under the row.\n"
        )

        #expect(draft.title == "feat: inline diff")
        #expect(draft.body == "Opens the diff under the row.")
        #expect(draft.commitCount == 1)
    }

    @Test func singleCommitWithoutBodyLeavesDescriptionEmpty() {
        let draft = PullRequestDraftBuilder.draft(
            branch: "feat/inline-diff",
            commits: [commit("feat: inline diff")],
            singleCommitMessage: "feat: inline diff"
        )

        #expect(draft.title == "feat: inline diff")
        #expect(draft.body.isEmpty)
    }

    @Test func severalCommitsUseTheBranchName() {
        let draft = PullRequestDraftBuilder.draft(
            branch: "feat/pull-requests",
            commits: [commit("second", hash: "b"), commit("first", hash: "a")]
        )

        #expect(draft.title == "feat/pull-requests")
        #expect(draft.commitCount == 2)
        // Oldest first, the order the work happened in.
        #expect(draft.body == "- first\n- second")
    }

    @Test func noCommitsStillNamesTheBranch() {
        let draft = PullRequestDraftBuilder.draft(branch: "feat/empty", commits: [])

        #expect(draft.title == "feat/empty")
        #expect(draft.body.isEmpty)
        #expect(draft.commitCount == 0)
    }

    @Test func singleCommitMissingItsMessageFallsBackToTheSummary() {
        let draft = PullRequestDraftBuilder.draft(
            branch: "fix/thing",
            commits: [commit("fix: thing")],
            singleCommitMessage: nil
        )

        #expect(draft.title == "fix: thing")
        #expect(draft.body.isEmpty)
    }
}
