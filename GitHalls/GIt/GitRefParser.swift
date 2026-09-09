//
//  GitRefParser.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation

/// Reads the `%D` decoration of a `--decorate=full` log.
///
/// The full form is what makes this parseable at all: with git's default short
/// decoration a local branch named `origin/main` is indistinguishable from the
/// remote-tracking ref, and a tag named `main` is only separable by a prefix.
/// With `refs/heads/` / `refs/remotes/` / `tag: refs/tags/` the answer is total.
enum GitRefParser {
    static func parse(_ decoration: String) -> [GitRef] {
        let trimmed = decoration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var refs: [GitRef] = []

        for piece in trimmed.components(separatedBy: ", ") {
            let token = piece.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }

            // "HEAD -> refs/heads/main" states two facts in one token: HEAD is
            // here, and it is attached to that branch.
            if let arrow = token.range(of: " -> ") {
                refs.append(GitRef(kind: .head, name: "HEAD", isHeadTarget: false))
                if let target = ref(from: String(token[arrow.upperBound...]), isHeadTarget: true) {
                    refs.append(target)
                }
                continue
            }

            if token == "HEAD" {  // detached
                refs.append(GitRef(kind: .head, name: "HEAD", isHeadTarget: false))
                continue
            }

            if let parsed = ref(from: token, isHeadTarget: false) {
                refs.append(parsed)
            }
        }

        // Sorted so the output is deterministic, and because that order is the
        // one the chips read best in: HEAD, local, remote, tag.
        return refs.sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
    }

    private static func ref(from token: String, isHeadTarget: Bool) -> GitRef? {
        if token.hasPrefix("tag: refs/tags/") {
            return GitRef(
                kind: .tag,
                name: String(token.dropFirst("tag: refs/tags/".count)),
                isHeadTarget: false
            )
        }

        if token.hasPrefix("refs/heads/") {
            return GitRef(
                kind: .localBranch,
                name: String(token.dropFirst("refs/heads/".count)),
                isHeadTarget: isHeadTarget
            )
        }

        if token.hasPrefix("refs/remotes/") {
            let name = String(token.dropFirst("refs/remotes/".count))
            // origin/HEAD is a symbolic alias for the default branch. Drawing it
            // puts a second chip on a commit that already says origin/main.
            guard !name.hasSuffix("/HEAD") else { return nil }
            return GitRef(kind: .remoteBranch, name: name, isHeadTarget: false)
        }

        // refs/notes/*, refs/pull/*, refs/stash — nothing the menu can act on.
        return nil
    }
}
