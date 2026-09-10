//
//  PullRequest.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 10/09/26.
//

import Foundation

/// The little `gh pr list` will say about a pull request that already exists.
struct PullRequestSummary: Identifiable, Hashable, Decodable {
    let number: Int
    let title: String
    let url: String

    var id: Int { number }
}

/// What the create sheet opens with.
struct PullRequestDraft: Equatable {
    var title: String
    var body: String

    /// How many commits the title was decided from, so the sheet can say what
    /// it based the guess on.
    var commitCount: Int
}

enum PullRequestDraftBuilder {
    /// A branch with one commit has already been described once, in that
    /// commit's own message — repeating the branch name there would throw away
    /// the better text. More than one commit has no single message to borrow,
    /// so the branch name is the only thing that names the whole of the work.
    ///
    /// `commits` comes in `git log` order, newest first.
    static func draft(
        branch: String,
        commits: [Commit],
        singleCommitMessage: String? = nil
    ) -> PullRequestDraft {
        guard commits.count != 1 else {
            let commit = commits[0]
            return PullRequestDraft(
                title: commit.summary,
                body: body(fromCommitMessage: singleCommitMessage, summary: commit.summary),
                commitCount: 1
            )
        }

        // Oldest first: the body reads as the order the work happened in, not
        // as the order git prints it.
        let summaries = commits.reversed().map { "- \($0.summary)" }
        return PullRequestDraft(
            title: branch,
            body: summaries.joined(separator: "\n"),
            commitCount: commits.count
        )
    }

    /// Everything after the subject line. The summary is already the title, and
    /// having it in both places is noise on every PR.
    private static func body(fromCommitMessage message: String?, summary: String) -> String {
        guard let message else { return "" }
        var lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.first?.trimmingCharacters(in: .whitespaces) == summary.trimmingCharacters(in: .whitespaces) {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
