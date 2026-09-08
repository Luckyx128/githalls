//
//  JiraIssueGrouping.swift
//  GitHalls
//

import Foundation

/// Issues sharing a status, as one column of the board holds them.
struct JiraIssueGroup: Identifiable, Equatable {
    let status: String
    let category: String
    let issues: [JiraIssue]

    var id: String { status }
    var isDone: Bool { category == "done" }
    var count: Int { issues.count }
}

/// Groups a flat JQL result by status, in board order.
///
/// Columns run left to right the way work flows: "new" statuses, then the ones
/// in progress, then "done". Within a category the order is the order Jira
/// returned — a project's own workflow order, which no sorting here could
/// guess. Statuses are project-specific strings; the category is the only
/// field that means the same thing everywhere.
enum JiraIssueGrouping {
    static func byStatus(_ issues: [JiraIssue]) -> [JiraIssueGroup] {
        var order: [String] = []
        var byStatus: [String: [JiraIssue]] = [:]
        var categoryOf: [String: String] = [:]

        for issue in issues {
            if byStatus[issue.status] == nil {
                byStatus[issue.status] = []
                categoryOf[issue.status] = issue.statusCategory
                order.append(issue.status)
            }
            byStatus[issue.status]?.append(issue)
        }

        // enumerated() keeps the arrival order as the tie-breaker, since sort
        // is not guaranteed stable.
        return order.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank(categoryOf[lhs.element] ?? "")
                let rhsRank = rank(categoryOf[rhs.element] ?? "")
                return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
            }
            .map { _, status in
                JiraIssueGroup(
                    status: status,
                    category: categoryOf[status] ?? "indeterminate",
                    issues: byStatus[status] ?? []
                )
            }
    }

    /// Keeps every column, with only the issues that match the text. An empty
    /// column still holds its place on the board.
    static func filter(_ groups: [JiraIssueGroup], by text: String) -> [JiraIssueGroup] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return groups }

        return groups.map {
            JiraIssueGroup(status: $0.status, category: $0.category, issues: $0.issues.filter { $0.matches(text) })
        }
    }

    private static func rank(_ category: String) -> Int {
        switch category {
        case "new": 0
        case "done": 2
        default: 1
        }
    }
}
