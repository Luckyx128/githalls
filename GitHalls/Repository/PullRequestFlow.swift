//
//  PullRequestFlow.swift
//  GitHalls
//

import Foundation

/// What happened to a pull request, as far as moving its issue goes.
enum PullRequestEvent: String, Codable, CaseIterable, Identifiable {
    case opened, approved, merged
    var id: Self { self }

    var label: String {
        switch self {
        case .opened: "is opened"
        case .approved: "is approved"
        case .merged: "is merged"
        }
    }

    var past: String {
        switch self {
        case .opened: "was opened"
        case .approved: "was approved"
        case .merged: "was merged"
        }
    }
}

/// One line of the table in Settings: "a pull request into `base` that `event`
/// offers to move its issue to `status`". The table is read top to bottom as
/// the team's flow, so a later line is a later stage.
struct PullRequestRule: Codable, Hashable, Identifiable {
    var id = UUID()

    /// A branch name ("dev", "origin/homologacao"), `*` for any branch, or
    /// `default` for the repository's default branch.
    var base: String

    var event: PullRequestEvent

    /// The status to offer. Empty means automatic: a review status for opened
    /// and approved, a done status for merged.
    var status: String

    static let anyBase = "*"
    static let defaultBase = "default"
}

/// The pull request that set an offer off, so the banner can say which one.
struct PullRequestTrigger: Hashable {
    let event: PullRequestEvent
    let base: String
    let number: Int
}

enum PullRequestFlowStore {
    private static let key = "issueLink.pullRequestRules"

    /// Safe for any repository: an opened pull request offers review, and only
    /// a merge into the default branch offers done. A merge into "dev" or
    /// "homologacao" offers nothing until the table says what it means.
    static let safeDefaults = [
        PullRequestRule(base: PullRequestRule.anyBase, event: .opened, status: ""),
        PullRequestRule(base: PullRequestRule.defaultBase, event: .merged, status: "")
    ]

    static var rules: [PullRequestRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let rules = try? JSONDecoder().decode([PullRequestRule].self, from: data)
            else { return safeDefaults }
            return rules
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
}

nonisolated enum PullRequestFlow {
    /// "origin/homologacao", "refs/heads/homologacao" and "Homologacao" are the
    /// same branch: what a pull request names is the bare branch, what people
    /// copy from a branch list often has the remote in front.
    static func normalize(_ branch: String) -> String {
        var name = branch.trimmingCharacters(in: .whitespaces).lowercased()
        for prefix in ["refs/heads/", "refs/remotes/", "remotes/"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        for remote in ["origin/", "upstream/"] where name.hasPrefix(remote) {
            name.removeFirst(remote.count)
        }
        return name
    }

    static func matches(_ ruleBase: String, base: String, defaultBranch: String?) -> Bool {
        let rule = normalize(ruleBase)
        if rule == PullRequestRule.anyBase { return true }
        if rule == PullRequestRule.defaultBase {
            return defaultBranch.map { normalize($0) == normalize(base) } ?? false
        }
        return rule == normalize(base)
    }

    /// The newest pull request into each base, with how many older ones into the
    /// same base it hides — a branch merged into "dev" six times reads as one
    /// line. Bases keep the order of their newest pull request.
    static func latestPerBase(_ pullRequests: [PullRequestStatus]) -> [(pullRequest: PullRequestStatus, earlier: Int)] {
        var order: [String] = []
        var newest: [String: PullRequestStatus] = [:]
        var counts: [String: Int] = [:]
        for pullRequest in pullRequests.sorted(by: { $0.number > $1.number }) {
            let base = normalize(pullRequest.baseRefName)
            if newest[base] == nil {
                order.append(base)
                newest[base] = pullRequest
            }
            counts[base, default: 0] += 1
        }
        return order.compactMap { base in newest[base].map { ($0, (counts[base] ?? 1) - 1) } }
    }

    /// The events a pull request has reached. A merged one is merged — it was
    /// opened once, but that is old news; a closed one reached nothing.
    static func events(of pullRequest: PullRequestStatus) -> [PullRequestEvent] {
        switch pullRequest.state {
        case .merged: [.merged]
        case .closed: []
        case .open: pullRequest.isApproved ? [.approved, .opened] : [.opened]
        }
    }

    /// The one move worth offering for an issue, given every pull request of
    /// its branch: the furthest stage of the table that some pull request has
    /// reached and the issue has not. Nil when there is none.
    ///
    /// - `includeAutomaticOpened`: an automatic "opened" line only counts right
    ///   after the app opened the pull request. On a later look it would offer
    ///   review to an issue that has long moved past it.
    static func move(
        pullRequests: [PullRequestStatus],
        rules: [PullRequestRule],
        defaultBranch: String?,
        transitions: [JiraTransition],
        currentStatus: String,
        currentCategory: String,
        includeAutomaticOpened: Bool
    ) -> (transition: JiraTransition, trigger: PullRequestTrigger)? {
        // Where the issue already stands in the table, by the statuses it names.
        let current = JiraText.fold(currentStatus)
        let reached = rules.lastIndex { !$0.status.isEmpty && JiraText.fold($0.status) == current } ?? -1

        for (index, rule) in rules.enumerated().reversed() where index > reached {
            if rule.status.isEmpty, rule.event == .opened, !includeAutomaticOpened { continue }

            guard let pullRequest = pullRequests.first(where: { pr in
                events(of: pr).contains(rule.event)
                    && matches(rule.base, base: pr.baseRefName, defaultBranch: defaultBranch)
            }) else { continue }

            guard let transition = target(of: rule, in: transitions, currentStatus: currentStatus, currentCategory: currentCategory)
            else { continue }

            return (transition, PullRequestTrigger(event: rule.event, base: pullRequest.baseRefName, number: pullRequest.number))
        }
        return nil
    }

    /// The move a line asks for, unless it goes nowhere or backwards.
    static func target(of rule: PullRequestRule, in transitions: [JiraTransition],
                       currentStatus: String, currentCategory: String) -> JiraTransition? {
        let transition: JiraTransition?
        if rule.status.isEmpty {
            transition = rule.event == .merged
                ? IssueLinkRules.doneTransition(in: transitions, currentCategory: currentCategory)
                : IssueLinkRules.reviewTransition(in: transitions, currentStatus: currentStatus)
        } else {
            let wanted = JiraText.fold(rule.status)
            transition = transitions.first { JiraText.fold($0.toStatus) == wanted }
                ?? transitions.first { JiraText.fold($0.toStatus).contains(wanted) }
        }

        guard let transition,
              JiraText.fold(transition.toStatus) != JiraText.fold(currentStatus),
              rank(transition.toStatusCategory) >= rank(currentCategory)
        else { return nil }
        return transition
    }

    /// To do, then in progress, then done: a move never goes down this.
    private static func rank(_ category: String) -> Int {
        switch category {
        case "new": 0
        case "done": 2
        default: 1
        }
    }
}
