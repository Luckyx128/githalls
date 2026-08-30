//
//  CommitLogParser.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 29/08/26.
//

import Foundation

enum CommitLogParser {
    private static let fieldSeparator: Character = "\u{1F}"   // unit separator
    private static let recordSeparator: Character = "\u{1E}"  // record separator

    static func parse(_ raw: String) -> [Commit] {
        raw.split(separator: recordSeparator, omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == 5 else { return nil }
            let trimmed = fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let date = ISO8601DateFormatter().date(from: trimmed[3]) else { return nil }
            return Commit(
                hash: trimmed[0],
                shortHash: trimmed[1],
                authorName: trimmed[2],
                date: date,
                summary: trimmed[4]
            )
        }
    }
}
