//
//  JiraComment.swift
//  GitHalls
//

import Foundation

/// One comment, already flattened from ADF to plain text.
struct JiraComment: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var author: JiraUser?
    var body: String
    var created: Date?
    var updated: Date?

    /// A comment shown before Jira has accepted it.
    var isPending: Bool { id.hasPrefix(Self.pendingPrefix) }

    static let pendingPrefix = "pending-"

    init(id: String, author: JiraUser? = nil, body: String, created: Date? = nil, updated: Date? = nil) {
        self.id = id
        self.author = author
        self.body = body
        self.created = created
        self.updated = updated
    }

    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? String else { return nil }

        self.init(
            id: id,
            author: JiraUser(json: raw["author"] as? [String: Any]),
            body: JiraADF.plainText(from: raw["body"]),
            created: (raw["created"] as? String).flatMap(JiraClient.timestamp.date(from:)),
            updated: (raw["updated"] as? String).flatMap(JiraClient.timestamp.date(from:))
        )
    }
}
