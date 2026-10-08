//
//  JiraNewIssue.swift
//  GitHalls
//

import Foundation

/// An issue about to be created — a subtask when `parentKey` names a parent.
struct JiraNewIssue: Equatable, Sendable {
    var projectKey: String
    var issueTypeID: String
    var summary: String

    /// Plain text; written to Jira as Atlassian Document Format.
    var description: String?
    var priorityID: String?
    var labels: [String] = []
    var componentIDs: [String] = []
    var assigneeAccountID: String?
    var parentKey: String?

    /// `yyyy-MM-dd`, the only shape Jira takes.
    var dueDate: String?

    /// Anything else the create screen asked for, required custom fields included.
    var extra: [JiraFieldUpdate] = []

    /// The `fields` object of `POST /issue`.
    var fields: [String: Any] {
        var fields: [String: Any] = [
            "project": ["key": projectKey],
            "issuetype": ["id": issueTypeID],
            "summary": summary
        ]
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["description"] = JiraADF.document(from: description)
        }
        if let priorityID { fields["priority"] = ["id": priorityID] }
        if !labels.isEmpty { fields["labels"] = labels }
        if !componentIDs.isEmpty { fields["components"] = componentIDs.map { ["id": $0] } }
        if let assigneeAccountID { fields["assignee"] = ["accountId": assigneeAccountID] }
        if let parentKey { fields["parent"] = ["key": parentKey] }
        if let dueDate { fields["duedate"] = dueDate }
        for update in extra { fields[update.field] = update.value.foundation }
        return fields
    }
}

/// One field of an issue set to a new value; `.null` clears it.
struct JiraFieldUpdate: Equatable, Hashable, Sendable {
    let field: String
    let value: JiraJSON

    static func summary(_ text: String) -> Self { .init(field: "summary", value: .string(text)) }

    /// Plain text in, ADF out; an empty text clears the description.
    static func description(_ text: String) -> Self {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let value = empty ? JiraJSON.null : JiraJSON(foundation: JiraADF.document(from: text)) ?? .null
        return .init(field: "description", value: value)
    }

    static func priority(id: String) -> Self { .init(field: "priority", value: .object(["id": .string(id)])) }

    static func labels(_ labels: [String]) -> Self { .init(field: "labels", value: .array(labels.map(JiraJSON.string))) }

    static func components(ids: [String]) -> Self {
        .init(field: "components", value: .array(ids.map { .object(["id": .string($0)]) }))
    }

    /// `yyyy-MM-dd`, or nil to clear.
    static func dueDate(_ date: String?) -> Self {
        .init(field: "duedate", value: date.map(JiraJSON.string) ?? .null)
    }

    static func storyPoints(fieldID: String, _ points: Double?) -> Self {
        .init(field: fieldID, value: points.map(JiraJSON.number) ?? .null)
    }

    /// Epic, parent or subtask parent; nil detaches.
    static func parent(_ key: String?) -> Self {
        .init(field: "parent", value: key.map { .object(["key": .string($0)]) } ?? .null)
    }

    static func custom(_ field: String, _ value: JiraJSON) -> Self { .init(field: field, value: value) }
}
