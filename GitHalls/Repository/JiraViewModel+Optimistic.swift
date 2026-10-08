//
//  JiraViewModel+Optimistic.swift
//  GitHalls
//

import Foundation

extension JiraViewModel {
    /// A write that shows its result first: the board copy is patched at once,
    /// the request follows, and a refusal puts the card back as it was.
    ///
    /// Same one-at-a-time rule as `write`. The rollback is skipped when a search
    /// landed meanwhile — that answer is newer than the card being restored.
    func optimistic(_ issue: JiraIssue,
                    confirmation: String,
                    patch: (JiraIssue) -> JiraIssue,
                    perform: (JiraClient) async throws -> Void) async -> Bool {
        guard let client = clientFactory() else {
            report(issue.key, JiraCredentialsError.missing.localizedDescription, failed: true)
            return false
        }

        guard busyIssues.insert(issue.key).inserted else { return false }
        defer { busyIssues.remove(issue.key) }

        let original = boardIssue(for: issue.key)
        let token = searchToken
        replace(issue.key, with: patch)

        do {
            try await perform(client)
            report(issue.key, confirmation, failed: false)
            return true
        } catch {
            if searchToken == token, let original { replace(issue.key) { _ in original } }
            report(issue.key, error.localizedDescription, failed: true)
            return false
        }
    }
}
