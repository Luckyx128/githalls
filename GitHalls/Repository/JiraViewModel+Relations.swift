//
//  JiraViewModel+Relations.swift
//  GitHalls
//

import Foundation

/// Links, parents, watchers and votes.
extension JiraViewModel {
    /// Links `issue` to `otherKey`. `direction` is how `issue` reads: with
    /// "blocks", `.outward` means `issue` blocks `otherKey`.
    @discardableResult
    func link(_ issue: JiraIssue, _ type: JiraLinkType, direction: JiraIssueLink.Direction, to otherKey: String) async -> Bool {
        let placeholder = JiraIssueLink(
            id: JiraComment.pendingPrefix + UUID().uuidString, typeName: type.name,
            label: direction == .outward ? type.outward : type.inward, direction: direction,
            issue: JiraIssueRef(key: otherKey, summary: otherKey)
        )

        // Jira's "inward" end is the one that reads "is blocked by".
        let (inward, outward) = direction == .outward ? (otherKey, issue.key) : (issue.key, otherKey)
        let ok = await optimistic(issue, confirmation: "\(issue.key) linked to \(otherKey).", patch: { current in
            var patched = current
            patched.links = current.links.map { $0 + [placeholder] }
            return patched
        }, perform: { client in
            try await client.link(type.name, inward: inward, outward: outward)
        })
        return ok
    }

    @discardableResult
    func unlink(_ issue: JiraIssue, _ link: JiraIssueLink) async -> Bool {
        await optimistic(issue, confirmation: "Link removed from \(issue.key).", patch: { current in
            var patched = current
            patched.links = current.links?.filter { $0.id != link.id }
            return patched
        }, perform: { client in
            try await client.deleteLink(id: link.id)
        })
    }

    /// Epic, parent or subtask parent; nil detaches.
    @discardableResult
    func setParent(_ issue: JiraIssue, _ parent: JiraIssueRef?) async -> Bool {
        await edit(issue, [.parent(parent?.key)]) {
            $0.parentKey = parent?.key
            $0.parentSummary = parent?.summary
        }
    }

    // MARK: - Votes

    func loadVotes(for key: String) async throws {
        votesByIssue[key] = try await client().votes(key: key)
    }

    /// Votes or takes the vote back; the count moves first.
    @discardableResult
    func setVote(_ voted: Bool, on key: String) async -> Bool {
        let before = votesByIssue[key] ?? JiraVotes(count: 0, hasVoted: false)
        guard before.hasVoted != voted else { return true }

        votesByIssue[key] = JiraVotes(count: max(0, before.count + (voted ? 1 : -1)), hasVoted: voted)

        do {
            let client = try client()
            if voted { try await client.vote(key: key) } else { try await client.unvote(key: key) }
            report(key, voted ? "Voted for \(key)." : "Vote removed from \(key).", failed: false)
            return true
        } catch {
            votesByIssue[key] = before
            report(key, error.localizedDescription, failed: true)
            return false
        }
    }

    // MARK: - Watchers

    func loadWatchers(for key: String) async throws {
        watchersByIssue[key] = try await client().watchers(key: key)
    }

    /// Starts or stops watching as the connected account.
    @discardableResult
    func setWatching(_ watching: Bool, on key: String) async -> Bool {
        let me: (accountID: String, displayName: String)
        do { me = try await myself() } catch {
            report(key, error.localizedDescription, failed: true)
            return false
        }
        return await setWatcher(JiraUser(accountID: me.accountID, displayName: me.displayName), watching: watching, on: key)
    }

    /// Adds or removes any user as a watcher.
    @discardableResult
    func setWatcher(_ user: JiraUser, watching: Bool, on key: String) async -> Bool {
        let before = watchersByIssue[key] ?? []
        if watching {
            guard !before.contains(where: { $0.accountID == user.accountID }) else { return true }
            watchersByIssue[key] = before + [user]
        } else {
            watchersByIssue[key] = before.filter { $0.accountID != user.accountID }
        }

        do {
            let client = try client()
            if watching {
                try await client.addWatcher(key: key, accountID: user.accountID)
            } else {
                try await client.removeWatcher(key: key, accountID: user.accountID)
            }
            report(key, watching ? "\(user.displayName) is watching \(key)." : "\(user.displayName) stopped watching \(key).", failed: false)
            return true
        } catch {
            watchersByIssue[key] = before
            report(key, error.localizedDescription, failed: true)
            return false
        }
    }
}
