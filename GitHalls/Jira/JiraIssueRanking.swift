//
//  JiraIssueRanking.swift
//  GitHalls
//

import Foundation

/// The local half of a rank: where a card lands in its column while Jira is
/// still being asked.
enum JiraIssueRanking {
    /// The groups with `key` moved next to the issue `position` names, or nil
    /// when that cannot be shown — the issue or its target is not on the board,
    /// or they sit in different columns (a move between columns is a
    /// transition, not a rank).
    static func moving(_ key: String, to position: JiraRankPosition, in groups: [JiraIssueGroup]) -> [JiraIssueGroup]? {
        let target: String
        switch position {
        case .before(let other), .after(let other): target = other
        }
        guard key != target,
              let groupIndex = groups.firstIndex(where: { group in
                  group.issues.contains { $0.key == key } && group.issues.contains { $0.key == target }
              })
        else { return nil }

        var issues = groups[groupIndex].issues
        guard let from = issues.firstIndex(where: { $0.key == key }) else { return nil }

        let moving = issues.remove(at: from)
        guard let targetIndex = issues.firstIndex(where: { $0.key == target }) else { return nil }

        switch position {
        case .before: issues.insert(moving, at: targetIndex)
        case .after: issues.insert(moving, at: targetIndex + 1)
        }

        var result = groups
        let old = groups[groupIndex]
        result[groupIndex] = JiraIssueGroup(status: old.status, category: old.category, issues: issues)
        return result
    }
}
