//
//  JiraProject.swift
//  GitHalls
//

import Foundation

struct JiraProject: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let key: String
    let name: String

    init(id: String, key: String, name: String) {
        self.id = id
        self.key = key
        self.name = name
    }

    init?(json raw: [String: Any]) {
        guard let key = raw["key"] as? String else { return nil }
        self.init(id: raw["id"] as? String ?? key, key: key, name: raw["name"] as? String ?? key)
    }
}

struct JiraIssueType: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    var isSubtask = false

    /// 0 is a story/task, 1 an epic, -1 a subtask.
    var hierarchyLevel = 0

    init(id: String, name: String, isSubtask: Bool = false, hierarchyLevel: Int = 0) {
        self.id = id
        self.name = name
        self.isSubtask = isSubtask
        self.hierarchyLevel = hierarchyLevel
    }

    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? String else { return nil }
        self.init(
            id: id,
            name: raw["name"] as? String ?? id,
            isSubtask: raw["subtask"] as? Bool ?? false,
            hierarchyLevel: raw["hierarchyLevel"] as? Int ?? 0
        )
    }
}

/// A choice in a picker: a priority, a component, a select-list option.
struct JiraFieldOption: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let label: String

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    /// Priorities and components say `name`; select options say `value`.
    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? String,
              let label = raw["name"] as? String ?? raw["value"] as? String
        else { return nil }
        self.init(id: id, label: label)
    }
}
