//
//  CommitGraphParser.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation

/// Parses the eight-field records `GitService.graphLog` asks git for.
///
/// Same separators as `CommitLogParser`, and one difference that matters:
/// `omittingEmptySubsequences: false`. A root commit has an empty `%P` and most
/// commits have an empty `%D`; dropping empty fields would shift every field
/// after them and fail the count check on exactly the commits the graph most
/// needs to get right.
enum CommitGraphParser {
    private static let fieldSeparator: Character = "\u{1F}"   // unit separator
    private static let recordSeparator: Character = "\u{1E}"  // record separator
    private static let fieldCount = 8

    static func parse(_ raw: String) -> [GraphCommit] {
        // One formatter for the whole log. At a thousand commits, allocating one
        // per record is real work for nothing.
        let formatter = ISO8601DateFormatter()

        return raw.split(separator: recordSeparator, omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == fieldCount else { return nil }
            let trimmed = fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            guard let authorDate = formatter.date(from: trimmed[4]) else { return nil }
            let committerDate = formatter.date(from: trimmed[5]) ?? authorDate

            return GraphCommit(
                commit: Commit(
                    hash: trimmed[0],
                    shortHash: trimmed[1],
                    authorName: trimmed[3],
                    date: authorDate,
                    summary: trimmed[7]
                ),
                parents: trimmed[2].split(separator: " ").map(String.init),
                refs: GitRefParser.parse(trimmed[6]),
                committerDate: committerDate
            )
        }
    }
}
