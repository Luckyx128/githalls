//
//  JiraPullRequestLink.swift
//  GitHalls
//

import Foundation

/// A pull request written onto an issue as a comment, which is how it shows up
/// for everyone watching the issue without Jira needing a GitHub integration.
enum JiraPullRequestLink {
    static func commentText(for pullRequest: PullRequestSummary) -> String {
        // Plain text with the URL spelled out: a markdown link would lose its
        // address when the comment is read back as plain text, and the
        // "already linked" check reads comments that way.
        "Pull request #\(pullRequest.number): \(escaped(pullRequest.title))\n\(pullRequest.url)"
    }

    /// The title is the author's text, not markdown: its brackets and stars
    /// must come out as typed.
    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]()#".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// Linking twice would only add noise; a comment that already carries the
    /// URL is the link.
    static func isLinked(_ pullRequest: PullRequestSummary, in comments: [JiraComment]) -> Bool {
        comments.contains { $0.body.contains(pullRequest.url) }
    }
}
