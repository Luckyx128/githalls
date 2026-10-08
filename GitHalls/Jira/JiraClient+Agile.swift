//
//  JiraClient+Agile.swift
//  GitHalls
//

import Foundation

/// Jira Software's Agile 1.0 API: boards, their columns, sprints, and ranking.
extension JiraClient {
    private static let agile = "/rest/agile/1.0"

    /// What a board card renders: the search card, plus what the cards show.
    private static let boardFields = [
        "summary", "status", "issuetype", "priority", "updated", "assignee",
        "labels", "duedate", "parent"
    ]

    func boards(projectKey: String? = nil) async throws -> [JiraBoard] {
        var query: [String: String] = [:]
        if let projectKey { query["projectKeyOrId"] = projectKey }

        return try await objects(path: Self.agile + "/board", key: "values", query: query)
            .compactMap(JiraBoard.init(json:))
    }

    /// Columns and the statuses behind them, the estimation field and the rank field.
    func boardConfiguration(boardID: Int) async throws -> JiraBoardConfiguration {
        guard let object = try await send(request(path: Self.agile + "/board/\(boardID)/configuration")) as? [String: Any],
              let configuration = JiraBoardConfiguration(json: object)
        else { throw JiraError.malformedResponse }
        return configuration
    }

    /// Scrum boards only; a kanban board answers 400.
    func sprints(boardID: Int, states: [JiraSprintState] = [.active, .future]) async throws -> [JiraSprint] {
        try await objects(path: Self.agile + "/board/\(boardID)/sprint", key: "values",
                          query: ["state": states.map(\.rawValue).joined(separator: ",")])
            .compactMap(JiraSprint.init(json:))
    }

    func boardIssues(boardID: Int, jql: String? = nil, startAt: Int = 0, limit: Int = 50,
                     storyPointsField: String? = nil) async throws -> JiraPage<JiraIssue> {
        try await issuePage(path: Self.agile + "/board/\(boardID)/issue", jql: jql, startAt: startAt, limit: limit,
                            storyPointsField: storyPointsField)
    }

    func sprintIssues(sprintID: Int, jql: String? = nil, startAt: Int = 0, limit: Int = 50,
                      storyPointsField: String? = nil) async throws -> JiraPage<JiraIssue> {
        try await issuePage(path: Self.agile + "/sprint/\(sprintID)/issue", jql: jql, startAt: startAt, limit: limit,
                            storyPointsField: storyPointsField)
    }

    /// Issues on the board that belong to no sprint.
    func backlogIssues(boardID: Int, jql: String? = nil, startAt: Int = 0, limit: Int = 50,
                       storyPointsField: String? = nil) async throws -> JiraPage<JiraIssue> {
        try await issuePage(path: Self.agile + "/board/\(boardID)/backlog", jql: jql, startAt: startAt, limit: limit,
                            storyPointsField: storyPointsField)
    }

    /// Up to 50 issues into the sprint. 204.
    func moveToSprint(_ sprintID: Int, keys: [String]) async throws {
        try await post(path: Self.agile + "/sprint/\(sprintID)/issue", body: ["issues": keys])
    }

    /// Takes the issues out of whatever sprint holds them. 204.
    func moveToBacklog(keys: [String]) async throws {
        try await post(path: Self.agile + "/backlog/issue", body: ["issues": keys])
    }

    /// Ranks the issues before or after another one.
    func rank(_ keys: [String], _ position: JiraRankPosition, rankFieldID: Int? = nil) async throws {
        var body: [String: Any] = ["issues": keys]
        switch position {
        case .before(let key): body["rankBeforeIssue"] = key
        case .after(let key): body["rankAfterIssue"] = key
        }
        if let rankFieldID { body["rankCustomFieldId"] = rankFieldID }

        var request = request(path: Self.agile + "/issue/rank", method: "PUT")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 204 when all went through; 207 lists each issue, and a 4xx entry means
        // that one was refused even though the call as a whole was answered.
        let answer = try await send(request) as? [String: Any]
        let failed = (answer?["entries"] as? [[String: Any]])?.first { ($0["status"] as? Int ?? 200) >= 400 }
        if let failed {
            let errors = failed["errors"] as? [String]
            throw JiraError.http(status: failed["status"] as? Int ?? 400, message: errors?.first)
        }
    }

    /// Single-issue convenience: exactly one of `before` and `after`.
    func rank(issueKey: String, before: String?, after: String?, rankFieldID: Int? = nil) async throws {
        if let before {
            try await rank([issueKey], .before(before), rankFieldID: rankFieldID)
        } else if let after {
            try await rank([issueKey], .after(after), rankFieldID: rankFieldID)
        } else {
            throw JiraError.http(status: 400, message: "Ranking needs an issue to rank before or after.")
        }
    }

    // MARK: - Helpers

    private func post(path: String, body: [String: Any]) async throws {
        var request = request(path: path, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(request)
    }

    private func issuePage(path: String, jql: String?, startAt: Int, limit: Int,
                           storyPointsField: String?) async throws -> JiraPage<JiraIssue> {
        var fields = Self.boardFields
        if let storyPointsField { fields.append(storyPointsField) }

        var query = ["startAt": String(startAt), "maxResults": String(limit), "fields": fields.joined(separator: ",")]
        if let jql, !jql.isEmpty { query["jql"] = jql }

        guard let object = try await send(request(path: Self.path(path, query: query))) as? [String: Any],
              let raw = object["issues"] as? [[String: Any]]
        else { throw JiraError.malformedResponse }

        let items = raw.compactMap { Self.issue(from: $0, storyPointsField: storyPointsField) }
        let next = startAt + raw.count
        let total = object["total"] as? Int ?? next
        return JiraPage(items: items, nextStart: raw.isEmpty || next >= total ? nil : next, nextPageToken: nil)
    }
}
