//
//  StatusParser.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation


enum StatusParser {
    static func parse(_ raw: String) -> [FileChange] {
        raw.split(separator: "\n").compactMap(parseLine)
    }
    
    private static func parseLine(_ line: Substring) -> FileChange? {
        guard line.count > 3 else { return nil}
        let chars = Array(line)
        let indexStatus = chars[0]
        let worktreeStatus = chars[1]
        let rest = String(chars[3...])
        
        if indexStatus == "R" || indexStatus == "C" {
            let parts = rest.components(separatedBy: " -> ")
            guard parts.count == 2 else {return nil}
            return FileChange(
                path: parts[1], originalPath: parts[0],
                indexStatus: indexStatus, worktreeStatus: worktreeStatus,
                status: indexStatus == "R" ? .renamed : .copied
            )
        }
        
        let status: FileChange.Status = switch (indexStatus, worktreeStatus) {
            case ("?", "?"): .untracked
            case ("U", _), (_, "U"): .unmerged
            case ("A", _): .added
            case ("D", _), (_, "D"): .deleted
            default: .modified
        }
        
        return FileChange(
            path: rest,
            originalPath: nil,
            indexStatus: indexStatus,
            worktreeStatus: worktreeStatus,
            status: status)
    }
}
