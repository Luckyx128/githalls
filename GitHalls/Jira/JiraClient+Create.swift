//
//  JiraClient+Create.swift
//  GitHalls
//

import Foundation

/// Creating and editing issues, with the create-metadata a form needs first.
extension JiraClient {
    /// Projects the user may browse, by name.
    func projects() async throws -> [JiraProject] {
        try await objects(path: "/rest/api/3/project/search", key: "values", query: ["orderBy": "name"])
            .compactMap(JiraProject.init(json:))
    }

    /// What can be created in the project — subtask types included, flagged.
    func issueTypes(projectKey: String) async throws -> [JiraIssueType] {
        let path = "/rest/api/3/issue/createmeta/" + Self.escape(projectKey) + "/issuetypes"
        // Cloud answers `issueTypes`; the paged shape of newer docs says `values`.
        let raw = try await objects(path: path, key: "issueTypes", fallbackKey: "values")
        return raw.compactMap(JiraIssueType.init(json:))
    }

    /// The fields of the create screen for this project and type, required ones flagged.
    func createFields(projectKey: String, issueTypeID: String) async throws -> [JiraCreateField] {
        let path = "/rest/api/3/issue/createmeta/" + Self.escape(projectKey)
            + "/issuetypes/" + Self.escape(issueTypeID)
        return try await objects(path: path, key: "fields", fallbackKey: "values")
            .compactMap(JiraCreateField.init(json:))
    }

    /// Creates the issue — a subtask when it has a parent — and answers its key.
    func create(_ issue: JiraNewIssue) async throws -> String {
        var request = request(path: "/rest/api/3/issue", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": issue.fields])

        guard let object = try await send(request) as? [String: Any], let key = object["key"] as? String
        else { throw JiraError.malformedResponse }
        return key
    }

    /// Writes the given fields and leaves the rest alone. 204, no body.
    func edit(key: String, _ updates: [JiraFieldUpdate]) async throws {
        guard !updates.isEmpty else { return }

        var fields: [String: Any] = [:]
        for update in updates { fields[update.field] = update.value.foundation }

        var request = request(path: Self.path(for: key, suffix: ""), method: "PUT")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])
        _ = try await send(request)
    }
}
