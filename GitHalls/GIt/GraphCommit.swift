//
//  GraphCommit.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation

/// A commit as the graph needs it: the History-mode commit plus the two things
/// only `--all`, `%P` and `%D` can tell you — where it came from, and what
/// points at it.
///
/// This wraps `Commit` rather than widening it. `Commit` is what a plain
/// `git log` of the current branch produces, and it carries no parents; a type
/// that promises a DAG has to be a type the compiler can tell apart from one
/// that does not, or a History-mode commit reaches the graph builder and
/// silently draws no edges at all.
struct GraphCommit: Identifiable, Hashable {
    let commit: Commit

    /// In git's own order. `parents[0]` is the first parent — the line the
    /// branch stays on. Empty for a root commit.
    let parents: [String]

    let refs: [GitRef]

    /// Not displayed. It is what you need the moment you have to explain why a
    /// commit sits where it does when its author date says otherwise.
    let committerDate: Date

    var id: String { commit.hash }
    var hash: String { commit.hash }
    var shortHash: String { commit.shortHash }
    var summary: String { commit.summary }
    var authorName: String { commit.authorName }
    var date: Date { commit.date }

    var isMerge: Bool { parents.count > 1 }
}

/// What `%D` names, once `--decorate=full` has made it unambiguous.
struct GitRef: Identifiable, Hashable {
    enum Kind: Int, Hashable, Comparable {
        case head = 0
        case localBranch = 1
        case remoteBranch = 2
        case tag = 3

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let kind: Kind

    /// "HEAD", "main", "origin/main", "v0.1.1" — never the refs/ prefix.
    let name: String

    /// The branch in `HEAD -> refs/heads/main`, as opposed to one that merely
    /// happens to point at the same commit.
    let isHeadTarget: Bool

    var id: String { "\(kind.rawValue):\(name)" }
}
