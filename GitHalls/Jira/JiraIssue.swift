//
//  JiraIssue.swift
//  GitHalls
//

import Foundation

/// One Jira issue. The search fills in what a card shows; the detail fetch
/// adds the rest (description, people, dates), which a list of a hundred
/// issues has no use for and would only make the search slower.
///
/// Codable and Hashable because the issue window is a scene that carries it:
/// SwiftUI restores that window across launches from the encoded value.
struct JiraIssue: Identifiable, Equatable, Hashable, Codable {
    let key: String
    let summary: String
    let status: String
    let statusCategory: String
    let type: String
    let priority: String?
    let updated: Date

    // MARK: - Detail fields

    var assigneeName: String?
    var reporterName: String?
    var created: Date?
    var labels: [String] = []

    /// The description as plain text, already flattened from Atlassian Document
    /// Format. `nil` means "not fetched yet", `""` means Jira has none — the
    /// window shows the two differently.
    var description: String?

    var id: String { key }

    var isDone: Bool { statusCategory == "done" }

    /// Case-insensitive match on the two things a person remembers: the key and
    /// the title.
    func matches(_ filter: String) -> Bool {
        let text = filter.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }

        return key.localizedCaseInsensitiveContains(text) || summary.localizedCaseInsensitiveContains(text)
    }
}
