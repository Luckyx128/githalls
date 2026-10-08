//
//  JiraCreateMetaCache.swift
//  GitHalls
//

import Foundation

/// createmeta, kept per project and issue type for the session. Quick-create
/// asks it before every submit, and the answer changes only when an admin edits
/// the create screen — not worth a request each time.
@MainActor
final class JiraCreateMetaCache {
    static let shared = JiraCreateMetaCache()

    private var types: [String: [JiraIssueType]] = [:]
    private var fields: [String: [JiraCreateField]] = [:]

    func issueTypes(projectKey: String, using authoring: any JiraIssueAuthoring) async throws -> [JiraIssueType] {
        if let cached = types[projectKey] { return cached }

        let loaded = try await authoring.issueTypes(projectKey: projectKey)
        types[projectKey] = loaded
        return loaded
    }

    func fields(projectKey: String, issueTypeID: String,
                using authoring: any JiraIssueAuthoring) async throws -> [JiraCreateField] {
        let key = projectKey + "|" + issueTypeID
        if let cached = fields[key] { return cached }

        let loaded = try await authoring.createFields(projectKey: projectKey, issueTypeID: issueTypeID)
        fields[key] = loaded
        return loaded
    }

    /// For when the account changes: another site, other screens.
    func clear() {
        types = [:]
        fields = [:]
    }
}
