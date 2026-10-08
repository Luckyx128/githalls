//
//  JiraAuthoringPlaceholders.swift
//  GitHalls
//

import Foundation

// TEMPORARY. Atlas (feat/jira-api) owns these types — see Docs/JIRA_API.md —
// and the names and shapes below mirror that document so this branch compiles
// before his lands. Delete this whole file when merging with feat/jira-api.

struct JiraUser: Equatable, Hashable, Sendable, Identifiable {
    var accountID: String
    var displayName: String
    var email: String?
    var avatarURL: URL?
    var active: Bool = true

    var id: String { accountID }
}

struct JiraProject: Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var key: String
    var name: String
}

struct JiraIssueType: Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var isSubtask: Bool
    var hierarchyLevel: Int
}

struct JiraFieldOption: Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
}

enum JiraFieldKind: Equatable, Hashable, Sendable {
    case string, number, date, dateTime, user, option, priority, labels, components, adf
    case other(String)
}

struct JiraCreateField: Equatable, Hashable, Sendable, Identifiable {
    var key: String
    var name: String
    var required: Bool
    var kind: JiraFieldKind
    var allowed: [JiraFieldOption] = []
    var hasDefault: Bool = false

    var id: String { key }
}

enum JiraJSON: Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JiraJSON])
    case object([String: JiraJSON])
}

struct JiraFieldUpdate: Equatable, Hashable, Sendable {
    var field: String
    var value: JiraJSON

    static func custom(_ field: String, _ value: JiraJSON) -> JiraFieldUpdate {
        JiraFieldUpdate(field: field, value: value)
    }
}

struct JiraNewIssue: Equatable, Hashable, Sendable {
    var projectKey: String
    var issueTypeID: String
    var summary: String
    var description: String?
    var priorityID: String?
    var labels: [String] = []
    var componentIDs: [String] = []
    var assigneeAccountID: String?
    var parentKey: String?
    var dueDate: String?
    var extra: [JiraFieldUpdate] = []
}
