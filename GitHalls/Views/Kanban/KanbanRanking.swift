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
/// protocol so the board ships before the client does; the real conformance
/// calls `JiraViewModel.rank(_:_:)` (feat/jira-api, JIRA_API.md Phase 3).
@MainActor
protocol KanbanRanking {
    /// False when Jira (or this build) refused; the board has already shown
    /// the card in its new place and puts it back.
    func rank(_ request: KanbanRankRequest) async -> Bool
}

/// Until the Agile client lands: every request is refused, with a reason.
@MainActor
struct KanbanRankingUnavailable: KanbanRanking {
    let jira: JiraViewModel

    func rank(_ request: KanbanRankRequest) async -> Bool {
        jira.actionFailed = true
        jira.actionMessage = "Reordering cards isn't available yet."
        return false
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
