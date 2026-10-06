//
//  Commit.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 29/08/26.
//

import Foundation

struct Commit: Identifiable, Hashable {
    let hash: String
    let shortHash: String
    let authorName: String
    let date: Date
    let summary: String

    /// Names from the `Co-authored-by:` trailers, in message order.
    var coAuthors: [String] = []

    var id: String { hash }

    /// Every name on the commit: "Ana", "Ana and Bruno", "Ana, Bruno and Caio".
    var allAuthorsLabel: String {
        ListFormatter.localizedString(byJoining: [authorName] + coAuthors)
    }

    /// The row-sized version: the author plus a count of the rest.
    var compactAuthorsLabel: String {
        coAuthors.isEmpty ? authorName : "\(authorName) +\(coAuthors.count)"
    }
}

enum CoAuthorTrailerParser {
    /// Group separator: what the log formats ask git to put between trailers.
    static let separator: Character = "\u{1D}"

    /// `Ana <ana@x.com>` → `Ana`. Duplicates go: a trailer pasted twice is
    /// still one person.
    static func parse(_ raw: Substring) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: separator).compactMap { value in
            let name = value.split(separator: "<", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
    }
}

struct CommitDetail {
    let commit: Commit
    let files: [CommitFile]

    /// Binaries are left out: git has no lines to count for them, and a total
    /// that silently treats them as zero would be a different number than the
    /// one the file rows add up to.
    var addedLineCount: Int { files.compactMap(\.addedLineCount).reduce(0, +) }

    var removedLineCount: Int { files.compactMap(\.removedLineCount).reduce(0, +) }
}
