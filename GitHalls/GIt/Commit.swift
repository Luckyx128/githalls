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

    var id: String { hash }
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
