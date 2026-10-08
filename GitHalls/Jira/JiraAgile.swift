//
//  JiraAgile.swift
//  GitHalls
//

import Foundation

struct JiraBoard: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String

    /// `scrum` or `kanban`; only scrum boards have sprints.
    let type: String
    var projectKey: String?

    var hasSprints: Bool { type == "scrum" }

    init(id: Int, name: String, type: String, projectKey: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.projectKey = projectKey
    }

    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? Int else { return nil }
        self.init(id: id, name: raw["name"] as? String ?? "Board \(id)",
                  type: raw["type"] as? String ?? "scrum",
                  projectKey: (raw["location"] as? [String: Any])?["projectKey"] as? String)
    }
}

/// One column of a board and the statuses that put a card in it. Statuses are
/// ids, as `JiraIssue.statusID` is: two statuses can share a name.
struct JiraBoardColumn: Identifiable, Equatable, Hashable, Sendable {
    let name: String
    let statusIDs: [String]
    var min: Int?
    var max: Int?

    var id: String { name }

    init(name: String, statusIDs: [String], min: Int? = nil, max: Int? = nil) {
        self.name = name
        self.statusIDs = statusIDs
        self.min = min
        self.max = max
    }
}

struct JiraBoardConfiguration: Equatable, Hashable, Sendable {
    let boardID: Int
    let name: String
    let columns: [JiraBoardColumn]

    /// The custom field estimates live in, e.g. `customfield_10016`.
    var estimationFieldID: String?

    /// The numeric id of the Rank field, which `rank` takes when a site has several.
    var rankFieldID: Int?

    /// The column a card with this status sits in; nil for a status the board
    /// does not show (the "unmapped" pool).
    func column(forStatusID statusID: String?) -> JiraBoardColumn? {
        guard let statusID else { return nil }
        return columns.first { $0.statusIDs.contains(statusID) }
    }

    init(boardID: Int, name: String, columns: [JiraBoardColumn], estimationFieldID: String? = nil, rankFieldID: Int? = nil) {
        self.boardID = boardID
        self.name = name
        self.columns = columns
        self.estimationFieldID = estimationFieldID
        self.rankFieldID = rankFieldID
    }

    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? Int else { return nil }

        let rawColumns = (raw["columnConfig"] as? [String: Any])?["columns"] as? [[String: Any]] ?? []
        let columns = rawColumns.map { column in
            JiraBoardColumn(
                name: column["name"] as? String ?? "",
                statusIDs: (column["statuses"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String },
                min: column["min"] as? Int,
                max: column["max"] as? Int
            )
        }

        self.init(
            boardID: id,
            name: raw["name"] as? String ?? "Board \(id)",
            columns: columns,
            estimationFieldID: ((raw["estimation"] as? [String: Any])?["field"] as? [String: Any])?["fieldId"] as? String,
            rankFieldID: (raw["ranking"] as? [String: Any])?["rankCustomFieldId"] as? Int
        )
    }
}

enum JiraSprintState: String, Equatable, Hashable, Sendable {
    case future, active, closed
}

struct JiraSprint: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
    let state: JiraSprintState
    var startDate: Date?
    var endDate: Date?
    var goal: String?
    var boardID: Int?

    init(id: Int, name: String, state: JiraSprintState, startDate: Date? = nil, endDate: Date? = nil,
         goal: String? = nil, boardID: Int? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.startDate = startDate
        self.endDate = endDate
        self.goal = goal
        self.boardID = boardID
    }

    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? Int else { return nil }

        // Sprint dates are ISO 8601 with a colon in the zone, unlike issues.
        func date(_ key: String) -> Date? {
            (raw[key] as? String).flatMap { Self.iso.date(from: $0) ?? Self.isoPlain.date(from: $0) }
        }

        self.init(
            id: id,
            name: raw["name"] as? String ?? "Sprint \(id)",
            state: (raw["state"] as? String).flatMap(JiraSprintState.init(rawValue:)) ?? .future,
            startDate: date("startDate"),
            endDate: date("endDate"),
            goal: raw["goal"] as? String,
            boardID: raw["originBoardId"] as? Int
        )
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain = ISO8601DateFormatter()
}

/// Where a ranked issue goes relative to another.
enum JiraRankPosition: Equatable, Hashable, Sendable {
    case before(String)
    case after(String)
}

/// One page of a long list, and how to ask for the next.
struct JiraPage<Element: Sendable>: Sendable {
    var items: [Element]

    /// `startAt` of the next page for the Agile and v3 offset APIs.
    var nextStart: Int?

    /// Cursor for the token-paged search; nil elsewhere.
    var nextPageToken: String?

    var isLast: Bool { nextStart == nil && nextPageToken == nil }
}
