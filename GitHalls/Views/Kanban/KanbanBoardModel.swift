//
//  KanbanBoardModel.swift
//  GitHalls
//

import Foundation
import Observation

/// A drop that more than one move can satisfy: the person has to say which.
struct KanbanMoveChoice: Identifiable, Equatable {
    let issue: JiraIssue
    let options: [JiraTransition]

    var id: String { issue.key }
}

/// What the board does with a drag, kept apart from `JiraViewModel` so the
/// request layer stays free of layout and animation concerns.
///
/// A dropped card moves at once and Jira is asked afterwards. The move lives
/// here as an overlay — `JiraViewModel` still holds the truth — so a refusal
/// removes the overlay and the card is simply where it always was.
@Observable
@MainActor
final class KanbanBoardModel {
    private let jira: JiraViewModel
    private let store: KanbanLayoutStore
    private let ranker: any KanbanRanking

    /// Layouts read from disk so far. Not observed: filling it is a cache fill,
    /// and a view is allowed to cause that while it reads. Changes go through
    /// `revision`, which is.
    @ObservationIgnored private var layouts: [String: KanbanColumnLayout] = [:]
    private var revision = 0

    var layout: KanbanColumnLayout {
        _ = revision
        let id = jira.selectedQuery.id

        if let cached = layouts[id] { return cached }

        let loaded = store.load(id)
        layouts[id] = loaded
        return loaded
    }

    /// Cards already shown in their new column, by key.
    private var pending: [String: (status: String, category: String, statusID: String?)] = [:]

    /// Set when several moves lead to the dropped-on column.
    var choice: KanbanMoveChoice?

    /// Bumped per refused key; the card shakes when its own count changes.
    private(set) var shakes: [String: Int] = [:]

    /// Card order a drag has already made, by status, until Jira answers.
    private var localOrder: [String: [String]] = [:]

    init(jira: JiraViewModel, store: KanbanLayoutStore = KanbanLayoutStore(), ranker: (any KanbanRanking)? = nil) {
        self.jira = jira
        self.store = store
        self.ranker = ranker ?? JiraKanbanRanking(jira: jira)
    }

    // MARK: - Columns

    /// Every column in the person's order, with in-flight moves applied.
    var allColumns: [JiraIssueGroup] {
        layout.ordered(applyingPending(to: jira.columns))
    }

    var visibleColumns: [JiraIssueGroup] { allColumns.filter { !layout.hidden.contains($0.status) } }

    /// In-flight moves applied to the issues, then the issues cut into columns.
    /// Patching the issue (status, id, category) and not the columns is what lets
    /// board columns and plain statuses share one path.
    private func applyingPending(to groups: [JiraIssueGroup]) -> [JiraIssueGroup] {
        var issues = groups.flatMap(\.issues)

        for index in issues.indices {
            guard let target = pending[issues[index].key] else { continue }

            issues[index].status = target.status
            issues[index].statusCategory = target.category
            issues[index].statusID = target.statusID
        }

        var regrouped = KanbanBoardColumns.group(issues, using: jira.boardConfiguration)

        // The filter hides cards, not columns: keep the empty ones it emptied.
        let present = Set(regrouped.map(\.status))
        regrouped += groups.filter { !present.contains($0.status) }

        guard !localOrder.isEmpty else { return regrouped }

        return regrouped.map { group in
            guard let keys = localOrder[group.status], Set(keys) == Set(group.issues.map(\.key)) else { return group }

            let byKey = Dictionary(uniqueKeysWithValues: group.issues.map { ($0.key, $0) })
            return JiraIssueGroup(status: group.status, category: group.category, issues: keys.compactMap { byKey[$0] })
        }
    }

    private func mutateLayout(_ change: (inout KanbanColumnLayout) -> Void) {
        var updated = layout
        change(&updated)

        let id = jira.selectedQuery.id
        layouts[id] = updated
        revision += 1
        store.save(updated, for: id)
    }

    func moveColumn(_ status: String, onto target: String) {
        let groups = allColumns
        mutateLayout { $0.move(status, onto: target, within: groups) }
    }

    func shiftColumn(_ status: String, by offset: Int) {
        let groups = allColumns
        mutateLayout { $0.shift(status, by: offset, within: groups) }
    }

    func toggleCollapsed(_ status: String) { mutateLayout { $0.toggleCollapsed(status) } }
    func toggleHidden(_ status: String) { mutateLayout { $0.toggleHidden(status) } }

    // MARK: - Board

    private static let boardKey = "kanban.boardID"

    /// Lists the boards once and returns to the one used last. Until a board is
    /// chosen the columns are plain statuses.
    func prepareBoards() async {
        guard jira.isConfigured else { return }

        if jira.boards.isEmpty { await jira.loadBoards() }

        guard jira.selectedBoard == nil,
              case let id = store.defaults.integer(forKey: Self.boardKey), id != 0,
              let board = jira.boards.first(where: { $0.id == id }) else { return }

        await jira.selectBoard(board)
    }

    /// nil goes back to columns made from the statuses on the board.
    func chooseBoard(_ board: JiraBoard?) async {
        store.defaults.set(board?.id ?? 0, forKey: Self.boardKey)

        guard let board else {
            jira.selectedBoard = nil
            jira.boardConfiguration = nil
            return
        }
        await jira.selectBoard(board)
    }

    // MARK: - Cards

    func issue(forKey key: String) -> JiraIssue? {
        allColumns.lazy.flatMap(\.issues).first { $0.key == key }
    }

    /// A card dropped on a column. Returns whether the drop was understood, which
    /// is all a drop target gets to say.
    @discardableResult
    func drop(cardKey key: String, onto status: String, before target: String? = nil) -> Bool {
        guard let issue = issue(forKey: key) else { return false }

        guard columnName(of: key) != status else {
            if let target { Task { await reorder(issue, before: target) } }
            return true
        }

        Task { await requestMove(issue, to: status) }
        return true
    }

    /// The column a card is in right now, which on a board is not its status.
    private func columnName(of key: String) -> String? {
        allColumns.first { $0.issues.contains { $0.key == key } }?.status
    }

    private func reorder(_ issue: JiraIssue, before target: String) async {
        guard let column = allColumns.first(where: { $0.issues.contains { $0.key == issue.key } }) else { return }

        let keys = column.issues.map(\.key)
        let reordered = KanbanOrdering.moving(issue.key, before: target, in: keys)
        guard reordered != keys, let request = KanbanOrdering.request(for: issue.key, in: reordered) else { return }

        localOrder[column.status] = reordered
        let succeeded = await ranker.rank(request)

        // Success: the view model now holds the order itself.
        localOrder[column.status] = nil
        if !succeeded { shakes[issue.key, default: 0] += 1 }
    }

    private func requestMove(_ issue: JiraIssue, to status: String) async {
        // The card goes first; the answer decides whether it stays. The column's
        // own category stands in until a transition says otherwise.
        let category = allColumns.first { $0.status == status }?.category ?? issue.statusCategory
        let boardColumn = jira.boardConfiguration?.columns.first { $0.name == status }
        pending[issue.key] = (status, category, boardColumn?.statusIDs.first)

        let transitions: [JiraTransition]
        do {
            transitions = try await jira.transitions(for: issue)
        } catch {
            refuse(issue, error.localizedDescription)
            return
        }

        let options = KanbanBoardColumns.transitions(transitions, into: status, using: jira.boardConfiguration)

        switch options.count {
        case 0:
            refuse(issue, "\(issue.key) can't move to \(status) from \(issue.status).")
        case 1:
            await perform(issue, options[0])
        default:
            pending[issue.key] = nil
            choice = KanbanMoveChoice(issue: issue, options: options)
        }
    }

    /// Runs a transition the person picked from the choice dialog.
    func choose(_ transition: JiraTransition) {
        guard let issue = choice?.issue else { return }

        choice = nil
        Task { await perform(issue, transition) }
    }

    private func perform(_ issue: JiraIssue, _ transition: JiraTransition) async {
        pending[issue.key] = (transition.toStatus, transition.toStatusCategory, transition.toStatusID)

        let succeeded = await jira.move(issue, to: transition)

        pending[issue.key] = nil
        if !succeeded { shakes[issue.key, default: 0] += 1 }
    }

    /// Nothing was optimistic yet, so there is nothing to undo: say why, shake.
    private func refuse(_ issue: JiraIssue, _ message: String) {
        pending[issue.key] = nil
        jira.actionFailed = true
        jira.actionMessage = message
        shakes[issue.key, default: 0] += 1
    }
}
