//
//  RecentBranchesStore.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 31/08/26.
//

import Foundation

enum RecentBranchesStore {
    private static let maxCount = 3

    private static func key(for repoURL: URL) -> String {
        "recentBranches:\(repoURL.path)"
    }

    static func load(for repoURL: URL) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(for: repoURL)) ?? []
    }

    static func addOrPromote(_ branchName: String, for repoURL: URL) {
        var names = load(for: repoURL)
        names.removeAll { $0 == branchName }
        names.insert(branchName, at: 0)
        if names.count > maxCount {
            names = Array(names.prefix(maxCount))
        }
        UserDefaults.standard.set(names, forKey: key(for: repoURL))
    }
}
