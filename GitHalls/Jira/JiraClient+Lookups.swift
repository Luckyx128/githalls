//
//  JiraClient+Lookups.swift
//  GitHalls
//

import Foundation

/// The pickers of an issue form: people, priorities, labels, components, fields.
extension JiraClient {
    /// Anyone on the site, matched by name or email.
    func searchUsers(query: String) async throws -> [JiraUser] {
        try await users(path: "/rest/api/3/user/search", query: ["query": query, "maxResults": "50"])
    }

    /// People an issue in this project can be assigned to.
    func searchAssignableUsers(query: String, projectKey: String) async throws -> [JiraUser] {
        try await users(path: "/rest/api/3/user/assignable/search",
                        query: ["query": query, "project": projectKey, "maxResults": "50"])
    }

    /// People the existing issue can be assigned to (workflow and permissions aware).
    func searchAssignableUsers(query: String, issueKey: String) async throws -> [JiraUser] {
        try await users(path: "/rest/api/3/user/assignable/search",
                        query: ["query": query, "issueKey": issueKey, "maxResults": "50"])
    }

    func priorities() async throws -> [JiraFieldOption] {
        guard let raw = try await send(request(path: "/rest/api/3/priority")) as? [[String: Any]]
        else { throw JiraError.malformedResponse }
        return raw.compactMap(JiraFieldOption.init(json:))
    }

    /// Labels in use on the site; with a query, the ones that match it.
    func labels(query: String? = nil) async throws -> [String] {
        let text = query?.trimmingCharacters(in: .whitespaces) ?? ""

        if text.isEmpty {
            return try await values(path: "/rest/api/3/label", key: "values").compactMap { $0 as? String }
        }

        let path = Self.path("/rest/api/3/jql/autocompletedata/suggestions",
                             query: ["fieldName": "labels", "fieldValue": text])
        guard let object = try await send(request(path: path)) as? [String: Any],
              let results = object["results"] as? [[String: Any]]
        else { throw JiraError.malformedResponse }
        return results.compactMap { $0["value"] as? String }
    }

    func components(projectKey: String) async throws -> [JiraFieldOption] {
        let path = "/rest/api/3/project/" + Self.escape(projectKey) + "/components"
        guard let raw = try await send(request(path: path)) as? [[String: Any]]
        else { throw JiraError.malformedResponse }
        return raw.compactMap(JiraFieldOption.init(json:))
    }

    /// Every field on the site, system and custom.
    func fields() async throws -> [JiraFieldInfo] {
        guard let raw = try await send(request(path: "/rest/api/3/field")) as? [[String: Any]]
        else { throw JiraError.malformedResponse }
        return raw.compactMap(JiraFieldInfo.init(json:))
    }

    // MARK: - Helpers

    private func users(path: String, query: [String: String]) async throws -> [JiraUser] {
        guard let raw = try await send(request(path: Self.path(path, query: query))) as? [[String: Any]]
        else { throw JiraError.malformedResponse }
        // Apps and deactivated accounts have no business in an assignee picker.
        return raw.compactMap { JiraUser(json: $0) }.filter { $0.active && $0.accountType != "app" }
    }

    /// A path with its query string percent-encoded the way Jira reads it.
    static func path(_ base: String, query: [String: String]) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))
        let pairs = query.sorted { $0.key < $1.key }.map { name, value in
            name + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
        }
        return pairs.isEmpty ? base : base + "?" + pairs.joined(separator: "&")
    }

    static func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? component
    }

    /// Every element of a paged `startAt`/`maxResults` answer, read to the end.
    /// Bounded, so a server that never says "last" cannot loop forever.
    func values(path: String, key: String, fallbackKey: String? = nil, query: [String: String] = [:]) async throws -> [Any] {
        var collected: [Any] = []
        var startAt = 0

        for _ in 0..<Self.maxPages {
            var page = query
            page["startAt"] = String(startAt)
            guard let object = try await send(request(path: Self.path(path, query: page))) as? [String: Any],
                  let items = object[key] as? [Any] ?? fallbackKey.flatMap({ object[$0] as? [Any] })
            else { throw JiraError.malformedResponse }

            collected += items
            startAt += items.count

            let isLast = object["isLast"] as? Bool
            let total = object["total"] as? Int
            if items.isEmpty || isLast == true || (isLast == nil && (total.map { startAt >= $0 } ?? true)) {
                break
            }
        }
        return collected
    }

    func objects(path: String, key: String, fallbackKey: String? = nil, query: [String: String] = [:]) async throws -> [[String: Any]] {
        try await values(path: path, key: key, fallbackKey: fallbackKey, query: query).compactMap { $0 as? [String: Any] }
    }

    static let maxPages = 20
}
