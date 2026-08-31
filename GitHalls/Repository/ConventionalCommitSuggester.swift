//
//  ConventionalCommitSuggester.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 31/08/26.
//

import Foundation

enum ConventionalCommitSuggester {
    static func suggestedType(for changes: [FileChange]) -> ConventionalCommitType {
        guard !changes.isEmpty else { return .chore }
        let paths = changes.map(\.path)

        if paths.allSatisfy({ $0.contains("Tests/") || $0.hasSuffix("Tests.swift") }) {
            return .test
        }
        if paths.allSatisfy({ $0.hasSuffix(".md") || $0.hasSuffix(".txt") }) {
            return .docs
        }
        if changes.allSatisfy({ $0.status == .added || $0.status == .untracked }) {
            return .feat
        }
        if changes.allSatisfy({ $0.status == .deleted }) {
            return .chore
        }
        return .fix
    }

    static func suggestedScope(for changes: [FileChange]) -> String? {
        let topLevelFolders = Set(changes.compactMap { change in
            change.path.split(separator: "/").first.map(String.init)
        })
        guard topLevelFolders.count == 1, let folder = topLevelFolders.first else { return nil }
        return folder.lowercased()
    }
}
