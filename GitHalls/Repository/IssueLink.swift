//
//  IssueLink.swift
//  GitHalls
//

import Foundation

/// What a push sent: the branch, and its commits newest first.
struct PushedWork: Equatable {
    let repositoryURL: URL
    let branch: String
    let commits: [Commit]
}

/// A branch, in some repository on this Mac, whose name carries an issue key.
struct LinkedBranch: Identifiable, Hashable {
    let repositoryURL: URL
    /// The short name: "feature/SWEB-1-pdf", never "origin/feature/SWEB-1-pdf".
    let name: String
    let isLocal: Bool
    let hasRemote: Bool
    let isCurrent: Bool
    /// Linked by hand rather than by the key in its name; only these unlink.
    var isManual = false
    /// Every pull request from this branch, one per base it was opened into.
    var pullRequests: [PullRequestStatus] = []

    var id: String { repositoryURL.path + "#" + name }
    var repositoryName: String { repositoryURL.lastPathComponent }
}

/// Something the link noticed and offers to do; never done without a click.
enum IssueLinkOffer: Identifiable, Equatable {
    /// A branch can carry several issues; the user picks which one to time.
    case startTimer([JiraIssue])
    case move(JiraIssue, JiraTransition, PullRequestTrigger)

    var id: String {
        switch self {
        case .startTimer(let issues): "timer:" + issues.map(\.key).joined(separator: ",")
        case .move(let issue, let transition, let trigger):
            "move:\(issue.key):\(transition.id):\(trigger.event.rawValue):\(trigger.base)"
        }
    }
}

/// Issues linked to a branch by hand: a branch whose name has no key, or one
/// that carries a second issue along with its own. Kept per repository, since
/// "develop" in one clone is not "develop" in another.
enum BranchLinkStore {
    private static let key = "issueLink.manualLinks"
    private static let separator = "\u{1F}"

    static func keys(repository: URL, branch: String, defaults: UserDefaults = .standard) -> [String] {
        (all(defaults)[id(repository, branch)] as? [String]) ?? []
    }

    static func link(_ issueKey: String, repository: URL, branch: String, defaults: UserDefaults = .standard) {
        update(repository, branch, defaults) { keys in
            if !keys.contains(issueKey.uppercased()) { keys.append(issueKey.uppercased()) }
        }
    }

    static func unlink(_ issueKey: String, repository: URL, branch: String, defaults: UserDefaults = .standard) {
        update(repository, branch, defaults) { keys in keys.removeAll { $0 == issueKey.uppercased() } }
    }

    /// Branches of `repository` linked by hand to `issueKey`.
    static func branches(linkedTo issueKey: String, repository: URL, defaults: UserDefaults = .standard) -> [String] {
        let prefix = repository.path + separator
        return all(defaults).compactMap { id, value in
            guard id.hasPrefix(prefix), (value as? [String])?.contains(issueKey.uppercased()) == true else { return nil }
            return String(id.dropFirst(prefix.count))
        }.sorted()
    }

    /// Every issue linked by hand to some branch of `repository`.
    static func linkedKeys(repository: URL, defaults: UserDefaults = .standard) -> Set<String> {
        let prefix = repository.path + separator
        return Set(all(defaults).filter { $0.key.hasPrefix(prefix) }.flatMap { ($0.value as? [String]) ?? [] })
    }

    private static func id(_ repository: URL, _ branch: String) -> String { repository.path + separator + branch }

    private static func all(_ defaults: UserDefaults) -> [String: Any] { defaults.dictionary(forKey: key) ?? [:] }

    private static func update(_ repository: URL, _ branch: String, _ defaults: UserDefaults, _ change: (inout [String]) -> Void) {
        var all = all(defaults)
        var keys = (all[id(repository, branch)] as? [String]) ?? []
        change(&keys)
        all[id(repository, branch)] = keys.isEmpty ? nil : keys
        defaults.set(all, forKey: key)
    }
}

/// The four switches in Settings › Jira › Branches. All on until turned off.
enum IssueLinkPreferences {
    static let postCommitsKey = "issueLink.postCommits"
    static let addKeyToCommitsKey = "issueLink.addKeyToCommits"
    static let offerMovesKey = "issueLink.offerMoves"
    static let offerTimerKey = "issueLink.offerTimer"

    static var postCommits: Bool { flag(postCommitsKey) }
    static var addKeyToCommits: Bool { flag(addKeyToCommitsKey) }
    static var offerMoves: Bool { flag(offerMovesKey) }
    static var offerTimer: Bool { flag(offerTimerKey) }

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

/// Commits already posted to an issue, so pushing the same commit again — a
/// second remote, a branch pushed twice — says nothing twice.
enum PostedCommitsStore {
    private static let key = "issueLink.postedCommits"
    private static let maxPerIssue = 300

    static func posted(on issueKey: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.dictionary(forKey: key)?[issueKey] as? [String]) ?? [])
    }

    static func record(_ hashes: [String], on issueKey: String, defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        var list = (all[issueKey] as? [String]) ?? []
        list.append(contentsOf: hashes.filter { !list.contains($0) })
        all[issueKey] = Array(list.suffix(maxPerIssue))
        defaults.set(all, forKey: key)
    }
}

nonisolated enum IssueLinkRules {
    /// The issues a branch belongs to: the key in its name first, then the
    /// ones linked by hand.
    static func keys(forBranch branch: String, manual: [String]) -> [String] {
        var keys = JiraIssueKey.all(in: branch)
        for key in manual where !keys.contains(key.uppercased()) { keys.append(key.uppercased()) }
        return keys
    }

    /// Which issues each commit belongs to. A branch linked to issues gives them
    /// every commit — two cards worked on one branch both hear about it.
    /// Otherwise a commit goes to the key in its own subject, and a commit that
    /// names none is left out. Keys keep the order they were first met in.
    static func group(_ commits: [Commit], branchKeys: [String]) -> [(key: String, commits: [Commit])] {
        guard branchKeys.isEmpty else { return branchKeys.map { ($0, commits) } }

        var order: [String] = []
        var byKey: [String: [Commit]] = [:]
        for commit in commits {
            guard let key = JiraIssueKey.find(in: commit.summary) else { continue }
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(commit)
        }
        return order.map { ($0, byKey[$0] ?? []) }
    }

    /// The comment a push leaves on its issue, in the markdown the comment
    /// writer turns into Jira's document format. Oldest commit first.
    static func comment(branch: String, repository: String, commits: [Commit], commitURL: (Commit) -> URL?) -> String {
        let count = commits.count
        let noun = count == 1 ? "commit enviado" : "commits enviados"
        var lines = ["**\(count) \(noun) para `\(branch)`** em \(escape(repository))", ""]
        for commit in commits.reversed() {
            let hash = "`\(commit.shortHash)`"
            let linked = commitURL(commit).map { "[\(hash)](\($0.absoluteString))" } ?? hash
            lines.append("- \(linked) \(escape(commit.summary))")
        }
        lines += ["", "_via GitHalls_"]
        return lines.joined(separator: "\n")
    }

    /// The move that puts an issue in review once its pull request is open:
    /// a status named for review in any of the languages admins type. Nil when
    /// the issue is already there or has no such move.
    static func reviewTransition(in transitions: [JiraTransition], currentStatus: String) -> JiraTransition? {
        guard !isReview(currentStatus) else { return nil }
        return transitions.first { isReview($0.toStatus) && $0.toStatusCategory != "done" }
    }

    /// The move that finishes an issue once its pull request is merged. A status
    /// in the done category, preferring the names that mean "done" over the ones
    /// that mean "cancelled".
    static func doneTransition(in transitions: [JiraTransition], currentCategory: String) -> JiraTransition? {
        guard currentCategory != "done" else { return nil }
        let done = transitions.filter { $0.toStatusCategory == "done" }
        let preferred = ["done", "conclu", "feito", "merged", "resolv", "pronto", "finaliz"]
        return done.first { transition in
            let name = JiraText.fold(transition.toStatus)
            return preferred.contains { name.contains($0) }
        } ?? done.first { transition in
            let name = JiraText.fold(transition.toStatus)
            return !["cancel", "won't", "wont", "descart", "rejeit"].contains { name.contains($0) }
        }
    }

    private static func isReview(_ status: String) -> Bool {
        let name = JiraText.fold(status)
        return ["review", "revis", "pull request", "code rev"].contains { name.contains($0) }
    }

    /// Markdown punctuation in a commit subject is text, not formatting.
    static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            if "\\`*_[]()#".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// "https://github.com/owner/repo/commit/<hash>", when the remote is GitHub.
    static func commitURL(remote: String?, hash: String) -> URL? {
        guard let remote, let (owner, repo) = GitHubService.ownerAndRepo(fromRemoteURL: remote) else { return nil }
        return URL(string: "https://github.com/\(owner)/\(repo)/commit/\(hash)")
    }
}
