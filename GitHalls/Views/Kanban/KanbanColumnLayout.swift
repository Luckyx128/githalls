//
//  KanbanColumnLayout.swift
//  GitHalls
//

import Foundation

/// How a person has arranged one board: column order, and which columns are
/// folded away or hidden. Keyed by status name, the only identity a column has.
struct KanbanColumnLayout: Codable, Equatable {
    var order: [String] = []
    var collapsed: Set<String> = []
    var hidden: Set<String> = []

    /// The columns in the saved order. A status the layout has never seen (a new
    /// column appearing after a move) keeps the board's own order and goes after
    /// the ones the person placed; a saved status with no column is ignored.
    func ordered(_ groups: [JiraIssueGroup]) -> [JiraIssueGroup] {
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        return groups.enumerated()
            .sorted { lhs, rhs in
                switch (position[lhs.element.status], position[rhs.element.status]) {
                case let (l?, r?): l < r
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    /// Puts `status` where `target` is. Dragging right lands after the target and
    /// dragging left lands before it, which is what the pointer expects.
    mutating func move(_ status: String, onto target: String, within groups: [JiraIssueGroup]) {
        var statuses = ordered(groups).map(\.status)

        guard status != target,
              let from = statuses.firstIndex(of: status),
              let to = statuses.firstIndex(of: target) else { return }

        statuses.remove(at: from)
        statuses.insert(status, at: to)
        order = statuses
    }

    /// Moves `status` past the next visible column; the keyboard's way to
    /// reorder. Hidden columns are stepped over, or a press would swap with
    /// something the person cannot see.
    mutating func shift(_ status: String, by offset: Int, within groups: [JiraIssueGroup]) {
        let statuses = ordered(groups).map(\.status)
        let step = offset < 0 ? -1 : 1

        guard let from = statuses.firstIndex(of: status) else { return }

        var to = from + step
        while statuses.indices.contains(to), hidden.contains(statuses[to]) { to += step }
        guard statuses.indices.contains(to) else { return }

        move(status, onto: statuses[to], within: groups)
    }

    mutating func toggleCollapsed(_ status: String) {
        if !collapsed.insert(status).inserted { collapsed.remove(status) }
    }

    mutating func toggleHidden(_ status: String) {
        if !hidden.insert(status).inserted { hidden.remove(status) }
    }
}

/// One saved layout per query: a board for "Active sprint" and one for "Assigned
/// to me" are different boards.
struct KanbanLayoutStore {
    var defaults: UserDefaults = .standard

    private func key(_ queryID: String) -> String { "kanban.layout.\(queryID)" }

    func load(_ queryID: String) -> KanbanColumnLayout {
        guard let data = defaults.data(forKey: key(queryID)),
              let layout = try? JSONDecoder().decode(KanbanColumnLayout.self, from: data) else {
            return KanbanColumnLayout()
        }
        return layout
    }

    func save(_ layout: KanbanColumnLayout, for queryID: String) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: key(queryID))
    }
}
