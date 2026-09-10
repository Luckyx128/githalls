//
//  MergeState.swift
//  GitHalls
//

import Foundation

/// A merge git started but could not finish on its own.
///
/// The working tree alone cannot answer "is this merge done?" — a fully
/// resolved merge looks exactly like a clean checkout in `git status`. So the
/// state is read from git itself: `MERGE_HEAD` says a merge is open, and
/// `ls-files --unmerged` says what is still in the way.
struct MergeState: Equatable {
    /// Paths git still considers unmerged. Empty means every conflict is settled.
    let unresolvedPaths: [String]

    /// Paths that still carry `<<<<<<<` / `>>>>>>>` — a file marked resolved
    /// without actually resolving it. Committing these is almost never intended.
    let markerPaths: [String]

    /// The message git prepared for the merge commit, `MERGE_MSG`.
    let preparedMessage: String?

    var isReadyToCommit: Bool { unresolvedPaths.isEmpty }
}

enum MergeStateParser {
    /// Paths from `git ls-files --unmerged`, which lists one line per stage —
    /// up to three for the same file. The caller wants files, not stages.
    static func unmergedPaths(_ raw: String) -> [String] {
        var paths: [String] = []
        for line in raw.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let path = String(line[line.index(after: tab)...])
            guard !path.isEmpty, !paths.contains(path) else { continue }
            paths.append(path)
        }
        return paths
    }

    /// Paths from `git diff --check`, which also reports whitespace problems.
    /// Only the conflict-marker lines matter here.
    static func conflictMarkerPaths(_ raw: String) -> [String] {
        let suffix = ": leftover conflict marker"
        var paths: [String] = []
        for line in raw.split(separator: "\n") {
            guard line.hasSuffix(suffix) else { continue }
            // "<path>:<line>: leftover conflict marker" — drop the message, then
            // the line number. A path may itself contain a colon, so this walks
            // back from the end rather than splitting on ":".
            let head = line.dropLast(suffix.count)
            guard let colon = head.lastIndex(of: ":") else { continue }
            let path = String(head[head.startIndex..<colon])
            guard !path.isEmpty, !paths.contains(path) else { continue }
            paths.append(path)
        }
        return paths
    }

    /// Splits `MERGE_MSG` into the two fields the commit form uses.
    ///
    /// Git appends a commented-out `# Conflicts:` block; those lines are
    /// instructions to a text editor, not part of the message.
    static func splitMessage(_ raw: String) -> (summary: String, description: String) {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("#") }

        guard let firstIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return ("", "")
        }

        let summary = String(lines[firstIndex]).trimmingCharacters(in: .whitespaces)
        let description = lines[lines.index(after: firstIndex)...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (summary, description)
    }
}
