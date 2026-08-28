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

}

extension FileChange {
    var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    var directoryPath: String {
        let components = path.split(separator: "/")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    var isStaged: Bool {
        indexStatus != " " && indexStatus != "?"
    }
}
