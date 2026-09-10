//
//  CommitFile.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 10/09/26.
//

import Foundation

/// One entry in a commit's list of touched files.
///
/// Deliberately holds no diff: a commit can touch two hundred files and only
/// the one being looked at is worth a `git show`. The counts come from
/// `--numstat`, which the same call that lists the paths already answers.
struct CommitFile: Identifiable, Hashable {
    let path: String

    /// Where the file came from, for renames and copies only.
    let originalPath: String?

    let status: FileChange.Status

    /// `nil` for a file git had no text to count — a binary.
    let addedLineCount: Int?
    let removedLineCount: Int?

    var id: String { originalPath.map { "\($0)->\(path)" } ?? path }

    var isBinary: Bool { addedLineCount == nil }

    var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    var directoryPath: String {
        let components = path.split(separator: "/")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    /// Both sides of a rename, so a `git show -- <pathspec>` keeps seeing it as
    /// one file instead of a delete next to an add.
    var pathspec: [String] {
        originalPath.map { [$0, path] } ?? [path]
    }
}

/// Reads `git show --raw --numstat`, whose two sections list the same files in
/// the same order — `--raw` for the status and the true paths, `--numstat` for
/// the line counts. Pairing them by position avoids having to undo the
/// `{old => new}` spelling numstat uses for renames.
enum CommitFileParser {
    static func parse(_ raw: String) -> [CommitFile] {
        var entries: [(path: String, originalPath: String?, status: FileChange.Status)] = []
        var counts: [(added: Int?, removed: Int?)] = []

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            // "::" is a combined merge diff, which carries one status per parent
            // and no single before-state to show. Callers ask for a first-parent
            // diff precisely so this does not turn up.
            if line.hasPrefix("::") { continue }

            if line.hasPrefix(":") {
                let fields = line.dropFirst().split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 2 else { continue }
                let statusCode = fields[0].split(separator: " ").last.map(String.init) ?? ""
                let status = status(for: statusCode)
                // A rename or a copy names both paths; everything else names one.
                if fields.count >= 3, status == .renamed || status == .copied {
                    entries.append((String(fields[2]), String(fields[1]), status))
                } else {
                    entries.append((String(fields[1]), nil, status))
                }
                continue
            }

            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            // "-" where a number should be: git counted no lines because there
            // are none to count.
            counts.append((Int(fields[0]), Int(fields[1])))
        }

        return entries.enumerated().map { index, entry in
            let count: (added: Int?, removed: Int?) = index < counts.count ? counts[index] : (nil, nil)
            return CommitFile(
                path: entry.path,
                originalPath: entry.originalPath,
                status: entry.status,
                addedLineCount: count.added,
                removedLineCount: count.removed
            )
        }
    }

    private static func status(for code: String) -> FileChange.Status {
        switch code.first {
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "U": return .unmerged
        // "T" is a type change — a file that became a symlink, say. It is still
        // the same path with different contents, which is what modified means
        // everywhere else in the app.
        default: return .modified
        }
    }
}
