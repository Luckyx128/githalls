//
//  KanbanRanking.swift
//  GitHalls
//

import Foundation

/// Where in a column a card should sit, in Jira's own terms: ranked next to
/// another issue. Exactly one of the two is set.
struct KanbanRankRequest: Equatable {
    let issueKey: String
    let before: String?
    let after: String?
}

/// The one thing the board needs from the Agile API to reorder cards. Behind a
/// protocol so the board's ordering can be tested without a Jira.
@MainActor
protocol KanbanRanking {
    /// False when Jira (or this build) refused; the board has already shown
    /// the card in its new place and puts it back.
    func rank(_ request: KanbanRankRequest) async -> Bool
}

/// Ranks through the view model, which reorders its own column at once and
/// puts it back on a refusal.
@MainActor
struct JiraKanbanRanking: KanbanRanking {
    let jira: JiraViewModel

    func rank(_ request: KanbanRankRequest) async -> Bool {
        guard let issue = jira.boardIssue(for: request.issueKey) else { return false }

        let position: JiraRankPosition
        if let before = request.before {
            position = .before(before)
        } else if let after = request.after {
            position = .after(after)
        } else {
            return false
        }
        return await jira.rank(issue, position)
    }
}

enum KanbanOrdering {
    /// `keys` with `key` taken out and put just before `target`.
    static func moving(_ key: String, before target: String, in keys: [String]) -> [String] {
        guard key != target, keys.contains(key), keys.contains(target) else { return keys }

        var result = keys.filter { $0 != key }
        result.insert(key, at: result.firstIndex(of: target) ?? result.endIndex)
        return result
    }

    /// The neighbour Jira should rank against for the order just made.
    static func request(for key: String, in keys: [String]) -> KanbanRankRequest? {
        guard let index = keys.firstIndex(of: key) else { return nil }

        if keys.indices.contains(index + 1) {
            return KanbanRankRequest(issueKey: key, before: keys[index + 1], after: nil)
        }
        if index > 0 {
            return KanbanRankRequest(issueKey: key, before: nil, after: keys[index - 1])
        }
        return nil
    }
}
