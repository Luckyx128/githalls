//
//  JiraWorklog.swift
//  GitHalls
//

import Foundation

struct JiraWorklog: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var author: JiraUser?
    var timeSpentSeconds: Int
    var started: Date?
    var comment: String

    /// A worklog shown before Jira has accepted it.
    var isPending: Bool { id.hasPrefix(JiraComment.pendingPrefix) }

    /// "1h 30m", the way Jira writes durations.
    var timeSpent: String { Self.format(seconds: timeSpentSeconds) }

    init(id: String, author: JiraUser? = nil, timeSpentSeconds: Int, started: Date? = nil, comment: String = "") {
        self.id = id
        self.author = author
        self.timeSpentSeconds = timeSpentSeconds
        self.started = started
        self.comment = comment
    }

    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? String, let seconds = raw["timeSpentSeconds"] as? Int else { return nil }

        self.init(
            id: id,
            author: JiraUser(json: raw["author"] as? [String: Any]),
            timeSpentSeconds: seconds,
            started: (raw["started"] as? String).flatMap(JiraClient.timestamp.date(from:)),
            comment: JiraADF.plainText(from: raw["comment"])
        )
    }

    static func format(seconds: Int) -> String {
        let minutes = (seconds + 30) / 60
        let (days, hours, rest) = (minutes / (8 * 60), minutes % (8 * 60) / 60, minutes % 60)
        let parts = [(days, "d"), (hours, "h"), (rest, "m")].filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0m" : parts.joined(separator: " ")
    }
}
