//
//  JiraClient+Relations.swift
//  GitHalls
//

import Foundation

/// Links, parents, watchers and votes: how an issue relates to other issues and people.
extension JiraClient {
    func linkTypes() async throws -> [JiraLinkType] {
        guard let object = try await send(request(path: "/rest/api/3/issueLinkType")) as? [String: Any],
              let raw = object["issueLinkTypes"] as? [[String: Any]]
        else { throw JiraError.malformedResponse }
        return raw.compactMap(JiraLinkType.init(json:))
    }

    /// "`outward` <type.outward> `inward`" — for "blocks", the blocker is the
    /// outward issue and the blocked one the inward. 201, no body.
    func link(_ typeName: String, inward: String, outward: String) async throws {
        var request = request(path: "/rest/api/3/issueLink", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": ["name": typeName],
            "inwardIssue": ["key": inward],
            "outwardIssue": ["key": outward]
        ])
        _ = try await send(request)
    }

    func deleteLink(id: String) async throws {
        _ = try await send(request(path: "/rest/api/3/issueLink/" + Self.escape(id), method: "DELETE"))
    }

    /// Epic, parent or subtask parent; nil detaches.
    func setParent(key: String, parentKey: String?) async throws {
        try await edit(key: key, [.parent(parentKey)])
    }

    // MARK: - Watchers

    func watchers(key: String) async throws -> [JiraUser] {
        guard let object = try await send(request(path: Self.path(for: key, suffix: "/watchers"))) as? [String: Any],
              let raw = object["watchers"] as? [[String: Any]]
        else { throw JiraError.malformedResponse }
        return raw.compactMap { JiraUser(json: $0) }
    }

    func addWatcher(key: String, accountID: String) async throws {
        var request = request(path: Self.path(for: key, suffix: "/watchers"), method: "POST")
        // The body is a bare JSON string, not an object — Jira's own quirk.
        request.httpBody = try JSONSerialization.data(withJSONObject: accountID, options: .fragmentsAllowed)
        _ = try await send(request)
    }

    func removeWatcher(key: String, accountID: String) async throws {
        let path = Self.path(Self.path(for: key, suffix: "/watchers"), query: ["accountId": accountID])
        _ = try await send(request(path: path, method: "DELETE"))
    }

    // MARK: - Votes

    func votes(key: String) async throws -> JiraVotes {
        guard let object = try await send(request(path: Self.path(for: key, suffix: "/votes"))) as? [String: Any]
        else { throw JiraError.malformedResponse }
        return JiraVotes(count: object["votes"] as? Int ?? 0, hasVoted: object["hasVoted"] as? Bool ?? false)
    }

    func vote(key: String) async throws {
        _ = try await send(request(path: Self.path(for: key, suffix: "/votes"), method: "POST"))
    }

    func unvote(key: String) async throws {
        _ = try await send(request(path: Self.path(for: key, suffix: "/votes"), method: "DELETE"))
    }
}
