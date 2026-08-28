//
//  FileChange.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation

struct FileChange: Identifiable, Hashable {
    enum Status {
        case modified, added, deleted, renamed, copied, untracked, unmerged
    }
    
    var id: String { originalPath.map { "\($0)->\(path)"} ??  path }
    let path: String
    let originalPath: String?
    let indexStatus: Character
    let worktreeStatus: Character
    let status: Status
    var isStaged: Bool {
        indexStatus != " " && indexStatus != "?"
    }
}
