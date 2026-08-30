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
    let fileDiffs: [FileDiff]
}
