//
//  JiraViewModel+Agile.swift
//  GitHalls
//

import Foundation

/// Boards, sprints and ranking.
extension JiraViewModel {
    func loadBoards(projectKey: String? = nil) async {
        do {
            boards = try await client().boards(projectKey: projectKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Makes the board current and loads its columns and sprints. A kanban board
    /// has no sprints, and asking would only earn a 400.
    func selectBoard(_ board: JiraBoard) async {
        selectedBoard = board
        boardConfiguration = nil
        sprints = []

        do {
            let client = try client()
            async let configuration = client.boardConfiguration(boardID: board.id)
            async let loaded = board.hasSprints ? client.sprints(boardID: board.id) : []

            let (config, found) = try await (configuration, loaded)
            guard selectedBoard?.id == board.id else { return }
            boardConfiguration = config
            sprints = found
        } catch {
            guard selectedBoard?.id == board.id else { return }
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func moveToSprint(_ issue: JiraIssue, _ sprint: JiraSprint) async -> Bool {
        let moved = await optimistic(issue, confirmation: "\(issue.key) moved to \(sprint.name).", patch: { $0 }, perform: { client in
            try await client.moveToSprint(sprint.id, keys: [issue.key])
        })
        // A sprint board's membership changed; the cards say nothing of sprints, so reload.
        if moved { invalidate() }
        return moved
    }

    @discardableResult
    func moveToBacklog(_ issue: JiraIssue) async -> Bool {
        let moved = await optimistic(issue, confirmation: "\(issue.key) moved to the backlog.", patch: { $0 }, perform: { client in
            try await client.moveToBacklog(keys: [issue.key])
        })
        if moved { invalidate() }
        return moved
    }

    /// Ranks the issue next to another and reorders its column at once; a
    /// refusal puts the column back.
    @discardableResult
    func rank(_ issue: JiraIssue, _ position: JiraRankPosition) async -> Bool {
        guard let client = clientFactory() else {
            report(issue.key, JiraCredentialsError.missing.localizedDescription, failed: true)
            return false
        }

        guard busyIssues.insert(issue.key).inserted else { return false }
        defer { busyIssues.remove(issue.key) }

        let token = searchToken
        let before = groups.first { $0.issues.contains { $0.key == issue.key } }
        if let reordered = JiraIssueRanking.moving(issue.key, to: position, in: groups) { groups = reordered }

        do {
            try await client.rank([issue.key], position, rankFieldID: boardConfiguration?.rankFieldID)
            report(issue.key, "\(issue.key) ranked.", failed: false)
            return true
        } catch {
            // Only the column that was reordered goes back; the rest of the
            // board may have moved on since.
            if searchToken == token, let before, let index = groups.firstIndex(where: { $0.id == before.id }) {
                groups[index] = before
            }
            report(issue.key, error.localizedDescription, failed: true)
            return false
        }
    }
}
