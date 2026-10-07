//
//  BranchCreator.swift
//  GitHalls
//

import Foundation

/// Git records no branch creator, so this is a guess from history: whoever
/// wrote the oldest commit the branch has that the default branch does not.
enum BranchCreator {
    /// The author of the first commit in `git log --reverse --format=%an`
    /// output. Nil for a branch with nothing of its own (just created, fully
    /// merged, or the default branch itself) — there is no one to name.
    static func firstAuthor(fromLog raw: String) -> String? {
        let first = raw.split(separator: "\n", omittingEmptySubsequences: true).first
        let name = first?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? nil : name
    }

    /// `git for-each-ref --format='%(objectname) %(refname)'` as refname -> tip.
    /// `refs/remotes/<remote>/HEAD` is skipped: it is a pointer to another
    /// branch, so listing it would only repeat that branch's answer.
    static func parseTips(_ raw: String) -> [String: String] {
        var tips: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let ref = String(parts[1])
            if ref.hasSuffix("/HEAD") { continue }
            tips[ref] = String(parts[0])
        }
        return tips
    }

    /// The full ref name for a listed branch.
    static func ref(for branch: Branch) -> String {
        (branch.isRemote ? "refs/remotes/" : "refs/heads/") + branch.name
    }

    /// What the row shows: "you" when the guess is the person using the app.
    static func label(for creator: String, currentUser: String?) -> String {
        guard let currentUser, !currentUser.isEmpty,
              creator.caseInsensitiveCompare(currentUser) == .orderedSame else { return creator }
        return "you"
    }

    static func tooltip(for label: String) -> String {
        "First commit on this branch by \(label) (inferred from history, git does not record who created a branch)"
    }
}
