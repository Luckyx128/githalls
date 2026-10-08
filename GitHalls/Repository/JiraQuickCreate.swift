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
    private let meta: JiraCreateMetaCache

    init(authoring: any JiraIssueAuthoring = JiraAuthoringFactory.make(),
         meta: JiraCreateMetaCache = .shared) {
        self.authoring = authoring
        self.meta = meta
    }

    /// The project key every card on the board shares — a board is one project
    /// in practice, and a key prefix is all a card carries.
    static func projectKey(from keys: [String]) -> String? {
        keys.first.flatMap { $0.split(separator: "-").dropLast().joined(separator: "-") }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// What the typed summary turned into.
    enum Outcome: Equatable {
        /// Created, and placed in the column when it could be.
        case created(String)

        /// The project asks for more than a summary: nothing was sent, and the
        /// full sheet should open with this.
        case needsSheet(CreateIssuePrefill)

        /// Nothing happened; `errorMessage` says why.
        case failed
    }

    /// Fields beyond the summary that Jira insists on and won't fill itself.
    /// Project, issue type and reporter are settled by the request or by Jira.
    static func extraRequirements(in fields: [JiraCreateField]) -> [JiraCreateField] {
        let settled: Set<String> = ["summary", "project", "issuetype", "reporter"]
        return fields.filter { $0.required && !$0.hasDefault && !settled.contains($0.key) }
    }

    /// The default type for a new card: a plain task, else any non-subtask.
    static func defaultType(in types: [JiraIssueType]) -> JiraIssueType? {
        types.first { $0.name == "Task" && !$0.isSubtask } ?? types.first { !$0.isSubtask }
    }

    /// Creates the issue when a summary is all the project asks for; hands back
    /// a prefill for the full sheet when it asks for more. A created issue is
    /// moved into the column's status — the board only hears about it after.
    func submit(status: String, board: JiraViewModel) async -> Outcome {
        let title = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreating else { return .failed }

        guard let projectKey = board.boardProjectKey else {
            errorMessage = "No project to create in yet."
            return .failed
        }

        isCreating = true
        defer { isCreating = false }

        do {
            guard let type = Self.defaultType(in: try await meta.issueTypes(projectKey: projectKey, using: authoring)) else {
                errorMessage = "This project has no issue type to create."
                return .failed
            }

            let fields = try await meta.fields(projectKey: projectKey, issueTypeID: type.id, using: authoring)
            if !Self.extraRequirements(in: fields).isEmpty {
                errorMessage = nil
                return .needsSheet(CreateIssuePrefill(summary: title, projectKey: projectKey,
                                                      issueTypeID: type.id, targetStatus: status))
            }

            let key = try await authoring.create(JiraNewIssue(projectKey: projectKey,
                                                              issueTypeID: type.id,
                                                              summary: title))
            summary = ""
            errorMessage = nil
            await Self.place(key, in: status, board: board)
            board.invalidate()
            return .created(key)
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    /// The move that lands a card in the column. By the board's column when it
    /// has one — a column can hold several statuses or carry its own name.
    static func move(into status: String, from moves: [JiraTransition],
                     using configuration: JiraBoardConfiguration?) -> JiraTransition? {
        KanbanBoardColumns.transitions(moves, into: status, using: configuration).first
    }

    /// Moves a new issue into the column it was typed in.
    static func place(_ key: String, in status: String, board: JiraViewModel) async {
        guard let issue = try? await board.fetchIssue(key: key),
              issue.status != status,
              let moves = try? await board.transitions(for: issue),
              let move = Self.move(into: status, from: moves, using: board.boardConfiguration)
        else { return }

        await board.move(issue, to: move)
    }
}

/// What the full Create Issue sheet opens with when quick-create can't do it
/// alone.
struct CreateIssuePrefill: Equatable, Identifiable {
    var summary: String
    var projectKey: String
    var issueTypeID: String

    /// The column's status; the new card is moved there after it is created.
    var targetStatus: String?

    var id: String { projectKey + "|" + issueTypeID + "|" + summary }
}
