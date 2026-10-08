//
//  JiraCreateField.swift
//  GitHalls
//

import Foundation

enum JiraFieldKind: Equatable, Hashable, Sendable {
    case string, number, date, dateTime, user, option, priority, labels, components, adf

    /// `timetracking`: written as `{"originalEstimate": "2h 30m"}`.
    case timeTracking

    /// The Team field; written as the team id string.
    case team

    /// An array of options, versions, groups…: written as `[{"id": …}]`.
    case multiOption

    /// An array of users: written as `[{"accountId": …}]`.
    case userList
    case other(String)
}

/// One field of the create screen for a project and issue type — what a "new
/// issue" form has to render, and which of them it has to insist on.
struct JiraCreateField: Identifiable, Equatable, Hashable, Sendable {
    let key: String
    let name: String
    var required = false
    var kind: JiraFieldKind = .string
    var allowed: [JiraFieldOption] = []
    var hasDefault = false

    /// Where Jira says candidates for this field can be searched, when it does
    /// (the Team field, user and group pickers).
    var autoCompleteURL: String?

    var id: String { key }

    init(key: String, name: String, required: Bool = false, kind: JiraFieldKind = .string,
         allowed: [JiraFieldOption] = [], hasDefault: Bool = false, autoCompleteURL: String? = nil) {
        self.key = key
        self.name = name
        self.required = required
        self.kind = kind
        self.allowed = allowed
        self.hasDefault = hasDefault
        self.autoCompleteURL = autoCompleteURL
    }

    init?(json raw: [String: Any]) {
        guard let key = raw["fieldId"] as? String ?? raw["key"] as? String else { return nil }

        let allowed = (raw["allowedValues"] as? [[String: Any]] ?? []).compactMap(JiraFieldOption.init(json:))
        self.init(
            key: key,
            name: raw["name"] as? String ?? key,
            required: raw["required"] as? Bool ?? false,
            kind: Self.kind(of: raw["schema"] as? [String: Any], hasAllowedValues: !allowed.isEmpty),
            allowed: allowed,
            hasDefault: raw["hasDefaultValue"] as? Bool ?? false,
            autoCompleteURL: raw["autoCompleteUrl"] as? String
        )
    }

    private static func kind(of schema: [String: Any]?, hasAllowedValues: Bool) -> JiraFieldKind {
        let type = schema?["type"] as? String ?? ""
        let items = schema?["items"] as? String
        let system = schema?["system"] as? String

        let custom = schema?["custom"] as? String ?? ""
        if system == "timetracking" || type == "timetracking" { return .timeTracking }
        if type == "team" || custom.contains("atlassian-team") || custom.contains("teams-custom-field-team") { return .team }

        switch type {
        case "string":
            // v3 takes rich-text fields as ADF: description, environment and
            // paragraph custom fields.
            return system == "description" || system == "environment" || custom.hasSuffix(":textarea") ? .adf : .string
        case "number": return .number
        case "date": return .date
        case "datetime": return .dateTime
        case "user": return .user
        case "priority": return .priority
        case "option": return .option
        case "array":
            switch items {
            case "string": return .labels
            case "component": return .components
            case "user": return .userList
            case "option", "version", "group", "project": return .multiOption
            default: return hasAllowedValues ? .multiOption : .other("array<\(items ?? "?")>")
            }
        default: return .other(type)
        }
    }
}

/// An entry of the site's field list. Custom fields have site-specific ids
/// (story points is `customfield_10016` on one site and something else on the
/// next), so the id is looked up by name instead of hard-coded.
struct JiraFieldInfo: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    var isCustom = false
    var schemaType: String?

    init(id: String, name: String, isCustom: Bool = false, schemaType: String? = nil) {
        self.id = id
        self.name = name
        self.isCustom = isCustom
        self.schemaType = schemaType
    }

    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? String, let name = raw["name"] as? String else { return nil }
        self.init(id: id, name: name, isCustom: raw["custom"] as? Bool ?? false,
                  schemaType: (raw["schema"] as? [String: Any])?["type"] as? String)
    }

    /// The numeric "Story Points" / "Story point estimate" field.
    static func storyPointsID(in fields: [JiraFieldInfo]) -> String? {
        let names = ["story point estimate", "story points"]
        for name in names {
            if let match = fields.first(where: {
                $0.name.lowercased() == name && $0.isCustom && ($0.schemaType ?? "number") == "number"
            }) { return match.id }
        }
        return nil
    }
}
