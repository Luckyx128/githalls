//
//  JiraQuickCreate.swift
//  GitHalls
//

import Foundation
import Observation

/// One-line create at the bottom of a board column: the summary is the only
/// thing asked, the project comes from the cards already in the column, and the
/// new issue is moved into that column's status after it is created.
@Observable
@MainActor
final class JiraQuickCreate {
    var summary = ""
    private(set) var isCreating = false
    var errorMessage: String?

    private let authoring: any JiraIssueAuthoring

    init(authoring: any JiraIssueAuthoring = JiraAuthoringFactory.make()) {
        self.authoring = authoring
    }

    /// The project key every card on the board shares — a board is one project
    /// in practice, and a key prefix is all a card carries.
    static func projectKey(from keys: [String]) -> String? {
        keys.first.flatMap { $0.split(separator: "-").dropLast().joined(separator: "-") }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The new key, or nil with `errorMessage` set. Creating succeeded if a key
    /// came back even when placing the card in the column did not; the board
    /// then shows it in its default status after the refresh.
    func submit(status: String, board: JiraViewModel) async -> String? {
        let title = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreating else { return nil }

        guard let projectKey = board.boardProjectKey else {
            errorMessage = "No project to create in yet."
            return nil
        }

        isCreating = true
        defer { isCreating = false }

        do {
            let types = try await authoring.issueTypes(projectKey: projectKey)
            guard let type = types.first(where: { $0.name == "Task" && !$0.isSubtask })
                    ?? types.first(where: { !$0.isSubtask })
            else {
                errorMessage = "This project has no issue type to create."
                return nil
            }

            let key = try await authoring.create(JiraNewIssue(projectKey: projectKey,
                                                              issueTypeID: type.id,
                                                              summary: title))
            summary = ""
            errorMessage = nil
            await place(key, in: status, board: board)
            board.invalidate()
            return key
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func place(_ key: String, in status: String, board: JiraViewModel) async {
        guard let issue = try? await board.fetchIssue(key: key),
              issue.status != status,
              let moves = try? await board.transitions(for: issue),
              // By the board's column when it has one: a column can hold several statuses.
              let move = KanbanBoardColumns.transitions(moves, into: status, using: board.boardConfiguration).first
        else { return }

        await board.move(issue, to: move)
    }
}
