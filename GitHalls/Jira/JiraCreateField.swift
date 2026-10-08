//
//  JiraCreateField.swift
//  GitHalls
//

import Foundation

enum JiraFieldKind: Equatable, Hashable, Sendable {
    case string, number, date, dateTime, user, option, priority, labels, components, adf
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

    var id: String { key }

    init(key: String, name: String, required: Bool = false, kind: JiraFieldKind = .string,
         allowed: [JiraFieldOption] = [], hasDefault: Bool = false) {
        self.key = key
        self.name = name
        self.required = required
        self.kind = kind
        self.allowed = allowed
        self.hasDefault = hasDefault
    }

    init?(json raw: [String: Any]) {
        guard let key = raw["fieldId"] as? String ?? raw["key"] as? String else { return nil }

        self.init(
            key: key,
            name: raw["name"] as? String ?? key,
            required: raw["required"] as? Bool ?? false,
            kind: Self.kind(of: raw["schema"] as? [String: Any]),
            allowed: (raw["allowedValues"] as? [[String: Any]] ?? []).compactMap(JiraFieldOption.init(json:)),
            hasDefault: raw["hasDefaultValue"] as? Bool ?? false
        )
    }

    private static func kind(of schema: [String: Any]?) -> JiraFieldKind {
        let type = schema?["type"] as? String ?? ""
        let items = schema?["items"] as? String
        let system = schema?["system"] as? String

        switch type {
        case "string": return system == "description" ? .adf : .string
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
            default: return .other("array<\(items ?? "?")>")
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
