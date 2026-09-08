//
//  JiraQuery.swift
//  GitHalls
//

import Foundation

/// One named JQL query the board can run: either a preset the app ships with
/// or one the user wrote and saved.
struct JiraQuery: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var jql: String

    /// Presets are code, not settings: this never round-trips to disk.
    var isBuiltIn: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, jql
    }

    init(id: String = UUID().uuidString, name: String, jql: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.jql = jql
        self.isBuiltIn = isBuiltIn
    }
}

/// The queries every board starts with. The sprint ones order by Rank — the
/// order the team put the cards in on their own board — and the rest by
/// recency, which is what a personal worklist wants.
enum JiraQueryPresets {
    static let activeSprintID = "preset:active-sprint"
    static let mySprintWorkID = "preset:my-sprint-work"
    static let assignedToMeID = "preset:assigned-to-me"
    static let reportedByMeID = "preset:reported-by-me"
    static let recentlyUpdatedID = "preset:recently-updated"

    static let all: [JiraQuery] = [
        JiraQuery(id: activeSprintID, name: "Active sprint",
                  jql: "sprint in openSprints() ORDER BY Rank ASC", isBuiltIn: true),
        JiraQuery(id: mySprintWorkID, name: "My work in the sprint",
                  jql: "sprint in openSprints() AND assignee = currentUser() ORDER BY Rank ASC", isBuiltIn: true),
        JiraQuery(id: assignedToMeID, name: "Assigned to me",
                  jql: "assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC", isBuiltIn: true),
        JiraQuery(id: reportedByMeID, name: "Reported by me",
                  jql: "reporter = currentUser() ORDER BY updated DESC", isBuiltIn: true),
        JiraQuery(id: recentlyUpdatedID, name: "Recently updated",
                  jql: "updated >= -7d ORDER BY updated DESC", isBuiltIn: true)
    ]

    /// The board opens on the active sprint: the cards the team is working on this week.
    static var `default`: JiraQuery { all.first { $0.id == activeSprintID }! }

    /// Presets first, in their fixed order, then the user's own. A saved query
    /// that reuses a preset id is ignored rather than allowed to shadow it.
    static func combine(custom: [JiraQuery]) -> [JiraQuery] {
        let presetIDs = Set(all.map(\.id))
        return all + custom.filter { !presetIDs.contains($0.id) }
    }
}

/// The user's own queries, kept beside the identities in UserDefaults.
enum JiraQueryStore {
    private static let queriesKey = "jiraCustomQueries"
    private static let selectedKey = "jiraSelectedQueryID"

    static func load() -> [JiraQuery] {
        guard let data = UserDefaults.standard.data(forKey: queriesKey),
              let queries = try? JSONDecoder().decode([JiraQuery].self, from: data)
        else { return [] }
        return queries
    }

    static func save(_ queries: [JiraQuery]) {
        // Only the user's own: a preset written here would come back as a
        // custom query, listed twice and deletable.
        let custom = queries.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        UserDefaults.standard.set(data, forKey: queriesKey)
    }

    static var selectedID: String? {
        get { UserDefaults.standard.string(forKey: selectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }
}
