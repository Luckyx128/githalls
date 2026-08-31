//
//  ConventionalCommitSuggester.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 31/08/26.
//

import Foundation

enum ConventionalCommitSuggester {
    static func suggestedType(
        for changes: [FileChange],
        numstat: [String: (additions: Int, deletions: Int)] = [:]
    ) -> ConventionalCommitType {
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
        if changes.allSatisfy({ $0.status == .renamed || $0.status == .copied }) {
            return .refactor
        }

        let totals = changes.reduce((additions: 0, deletions: 0)) { acc, change in
            let stat = numstat[change.path] ?? (0, 0)
            return (acc.additions + stat.additions, acc.deletions + stat.deletions)
        }
        return suggestedType(forModifiedTotals: totals)
    }

    private static func suggestedType(forModifiedTotals totals: (additions: Int, deletions: Int)) -> ConventionalCommitType {
        let total = totals.additions + totals.deletions
        guard total > 0 else { return .chore }

        if totals.deletions == 0 || totals.additions > totals.deletions * 3 {
            return .feat
        }
        if total > 20 && totals.additions > 0 && totals.deletions > 0 {
            return .refactor
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
