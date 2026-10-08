//
//  KanbanBoardColumns.swift
//  GitHalls
//

import Foundation

/// Shapes a flat list of issues into columns.
///
/// Without a board configuration a column is a status, and only the statuses
/// present get one. With one, a column is whatever the board says — possibly
/// several statuses, possibly none of them present — so an empty "Review"
/// still exists to be dropped onto. Issues the board does not map (or with no
/// status id yet) keep a column of their own status after the board's.
enum KanbanBoardColumns {
    static func group(_ issues: [JiraIssue], using configuration: JiraBoardConfiguration?) -> [JiraIssueGroup] {
        guard let configuration, !configuration.columns.isEmpty else { return JiraIssueGrouping.byStatus(issues) }

        let mapped = issues.filter { configuration.column(forStatusID: $0.statusID) != nil }
        let unmapped = issues.filter { configuration.column(forStatusID: $0.statusID) == nil }

        let boardColumns = configuration.columns.enumerated().map { index, column in
            let inside = mapped.filter { column.statusIDs.contains($0.statusID ?? "") }

            return JiraIssueGroup(
                status: column.name,
                category: inside.first?.statusCategory ?? guessedCategory(index, of: configuration.columns.count),
                issues: inside
            )
        }

        // A status the board does not map may still share a column's name; its
        // cards must not vanish into, or be hidden by, that column.
        let taken = Set(boardColumns.map(\.status))
        let extra = JiraIssueGrouping.byStatus(unmapped).map { group in
            taken.contains(group.status)
                ? JiraIssueGroup(status: "\(group.status) (not on board)", category: group.category, issues: group.issues)
                : group
        }

        return boardColumns + extra
    }

    /// The transitions that land a card in `column`: by status id when the board
    /// knows the column, by name otherwise.
    static func transitions(_ transitions: [JiraTransition], into column: String,
                            using configuration: JiraBoardConfiguration?) -> [JiraTransition] {
        if let boardColumn = configuration?.columns.first(where: { $0.name == column }) {
            return transitions.filter { boardColumn.statusIDs.contains($0.toStatusID ?? "") || $0.toStatus == column }
        }
        return transitions.filter { $0.toStatus == column }
    }

    /// An empty column has no card to say what it is. Position is a fair guess:
    /// work flows from new to done.
    private static func guessedCategory(_ index: Int, of count: Int) -> String {
        if index == 0 { return "new" }
        return index == count - 1 ? "done" : "indeterminate"
    }
}
