//
//  JiraRelations.swift
//  GitHalls
//

import Foundation

/// A short reference to another issue: enough for a list row.
struct JiraIssueRef: Identifiable, Equatable, Hashable, Codable, Sendable {
    let key: String
    let summary: String
    var status: String
    var statusCategory: String
    var type: String

    var id: String { key }

    init(key: String, summary: String, status: String = "", statusCategory: String = "indeterminate", type: String = "Task") {
        self.key = key
        self.summary = summary
        self.status = status
        self.statusCategory = statusCategory
        self.type = type
    }

    init?(json raw: [String: Any]?) {
        guard let raw, let key = raw["key"] as? String else { return nil }

        let fields = raw["fields"] as? [String: Any]
        let status = fields?["status"] as? [String: Any]
        self.init(
            key: key,
            summary: fields?["summary"] as? String ?? key,
            status: status?["name"] as? String ?? "",
            statusCategory: (status?["statusCategory"] as? [String: Any])?["key"] as? String ?? "indeterminate",
            type: (fields?["issuetype"] as? [String: Any])?["name"] as? String ?? "Task"
        )
    }
}

struct JiraLinkType: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String

    /// How each end reads: "is blocked by" / "blocks".
    let inward: String
    let outward: String

    init?(json raw: [String: Any]) {
        guard let name = raw["name"] as? String else { return nil }
        id = raw["id"] as? String ?? name
        self.name = name
        inward = raw["inward"] as? String ?? name
        outward = raw["outward"] as? String ?? name
    }

    init(id: String, name: String, inward: String, outward: String) {
        self.id = id
        self.name = name
        self.inward = inward
        self.outward = outward
    }
}

/// A link as seen from one issue: `label` reads "<this issue> <label> <issue>".
struct JiraIssueLink: Identifiable, Equatable, Hashable, Codable, Sendable {
    enum Direction: String, Codable, Sendable { case inward, outward }

    let id: String
    let typeName: String
    let label: String
    let direction: Direction
    let issue: JiraIssueRef

    init(id: String, typeName: String, label: String, direction: Direction, issue: JiraIssueRef) {
        self.id = id
        self.typeName = typeName
        self.label = label
        self.direction = direction
        self.issue = issue
    }

    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? String else { return nil }

        let type = raw["type"] as? [String: Any]
        let name = type?["name"] as? String ?? ""

        // `inwardIssue` means the other issue is the inward end, so this one
        // reads with the inward phrase: on the blocked issue, "is blocked by".
        if let other = JiraIssueRef(json: raw["inwardIssue"] as? [String: Any]) {
            self.init(id: id, typeName: name, label: type?["inward"] as? String ?? name, direction: .inward, issue: other)
        } else if let other = JiraIssueRef(json: raw["outwardIssue"] as? [String: Any]) {
            self.init(id: id, typeName: name, label: type?["outward"] as? String ?? name, direction: .outward, issue: other)
        } else {
            return nil
        }
    }
}

struct JiraVotes: Equatable, Sendable {
    var count: Int
    var hasVoted: Bool
}
