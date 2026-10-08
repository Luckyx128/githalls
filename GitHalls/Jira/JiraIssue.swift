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
    var summary: String

    /// `var`, unlike the rest: a move rewrites these two on the board copy
    /// rather than costing a second search to find out where the card landed.
    var status: String
    var statusCategory: String

    let type: String
    var priority: String?
    let updated: Date

    // MARK: - Detail fields

    var assigneeName: String?

    /// Who Jira says it is assigned to, in the form an assign has to be written
    /// back in. The display name cannot be sent back.
    var assigneeAccountID: String?

    var reporterName: String?
    var created: Date?
    var labels: [String] = []

    /// The description as plain text, already flattened from Atlassian Document
    /// Format. `nil` means "not fetched yet", `""` means Jira has none — the
    /// window shows the two differently.
    var description: String?

    // MARK: - Planning fields
    //
    // Optional, never defaulted arrays: a window restored from an older launch
    // decodes without these keys, and nil also says "not fetched".

    /// The status id, which is what a board column lists (names can repeat).
    var statusID: String?

    /// `yyyy-MM-dd`.
    var dueDate: String?
    var components: [String]?
    var storyPoints: Double?
    var parentKey: String?
    var parentSummary: String?
    var subtasks: [JiraIssueRef]?
    var links: [JiraIssueLink]?

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
