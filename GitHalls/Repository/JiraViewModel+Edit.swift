//
//  JiraViewModel+Edit.swift
//  GitHalls
//

import Foundation

/// Creating and editing issues, and the lookups the forms are built from.
extension JiraViewModel {
    // MARK: - Create

    /// Creates the issue and answers its key; the board reloads to pick it up.
    func create(_ draft: JiraNewIssue) async -> String? {
        do {
            let key = try await client().create(draft)
            report(key, "\(key) created.", failed: false)
            invalidate()
            return key
        } catch {
            report(draft.projectKey, error.localizedDescription, failed: true)
            return nil
        }
    }

    func projects() async throws -> [JiraProject] { try await client().projects() }

    func issueTypes(projectKey: String) async throws -> [JiraIssueType] {
        try await client().issueTypes(projectKey: projectKey)
    }

    func createFields(projectKey: String, issueTypeID: String) async throws -> [JiraCreateField] {
        try await client().createFields(projectKey: projectKey, issueTypeID: issueTypeID)
    }

    // MARK: - Lookups

    func assignableUsers(query: String, projectKey: String) async throws -> [JiraUser] {
        try await client().searchAssignableUsers(query: query, projectKey: projectKey)
    }

    func priorities() async throws -> [JiraFieldOption] { try await client().priorities() }

    func labels(matching query: String?) async throws -> [String] { try await client().labels(query: query) }

    func components(projectKey: String) async throws -> [JiraFieldOption] {
        try await client().components(projectKey: projectKey)
    }

    /// The site's story points field, asked once: it never changes under us.
    func storyPointsFieldID() async throws -> String? {
        if let cached = storyPointsFieldCache { return cached }

        let id = JiraFieldInfo.storyPointsID(in: try await client().fields())
        storyPointsFieldCache = .some(id)
        return id
    }

    // MARK: - Edit

    /// Writes the fields; `patch` is what the card shows meanwhile.
    @discardableResult
    func edit(_ issue: JiraIssue,
              _ updates: [JiraFieldUpdate],
              patch: @escaping (inout JiraIssue) -> Void = { _ in }) async -> Bool {
        await optimistic(issue, confirmation: "\(issue.key) updated.", patch: { current in
            var patched = current
            patch(&patched)
            return patched
        }, perform: { client in
            try await client.edit(key: issue.key, updates)
        })
    }

    @discardableResult
    func setSummary(_ issue: JiraIssue, _ summary: String) async -> Bool {
        await edit(issue, [.summary(summary)]) { $0.summary = summary }
    }

    @discardableResult
    func setDescription(_ issue: JiraIssue, _ text: String) async -> Bool {
        await edit(issue, [.description(text)]) { $0.description = text }
    }

    @discardableResult
    func setPriority(_ issue: JiraIssue, _ priority: JiraFieldOption) async -> Bool {
        await edit(issue, [.priority(id: priority.id)]) { $0.priority = priority.label }
    }

    @discardableResult
    func setLabels(_ issue: JiraIssue, _ labels: [String]) async -> Bool {
        await edit(issue, [.labels(labels)]) { $0.labels = labels }
    }

    @discardableResult
    func setComponents(_ issue: JiraIssue, _ components: [JiraFieldOption]) async -> Bool {
        await edit(issue, [.components(ids: components.map(\.id))]) { $0.components = components.map(\.label) }
    }

    /// `yyyy-MM-dd`, or nil to clear.
    @discardableResult
    func setDueDate(_ issue: JiraIssue, _ date: String?) async -> Bool {
        await edit(issue, [.dueDate(date)]) { $0.dueDate = date }
    }

    @discardableResult
    func setStoryPoints(_ issue: JiraIssue, _ points: Double?) async -> Bool {
        do {
            guard let field = try await storyPointsFieldID() else {
                report(issue.key, "This Jira site has no story points field.", failed: true)
                return false
            }
            return await edit(issue, [.storyPoints(fieldID: field, points)]) { $0.storyPoints = points }
        } catch {
            report(issue.key, error.localizedDescription, failed: true)
            return false
        }
    }
}
