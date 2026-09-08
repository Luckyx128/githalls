//
//  JiraTransition.swift
//  GitHalls
//

import Foundation

/// One edge out of the issue's current status, as its project's workflow allows
/// it right now.
///
/// The target status and its category are carried along, not just the id: a
/// move that knows where it lands lets the board be corrected in place, with no
/// second request to discover what everyone already knew.
struct JiraTransition: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let toStatus: String
    let toStatusCategory: String

    /// Jira will ask for more fields before it accepts this one — a required
    /// resolution, say — so a bare POST is refused.
    var hasScreen = false

    var leadsToInProgress: Bool { toStatusCategory == "indeterminate" }
}
