//
//  RecentRepositoriesStore.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 28/08/26.
//

import Foundation

enum RecentRepositoriesStore {
    private static let key = "recentRepositoryPaths"
    private static let maxCount = 10

    static func load() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    static func addOrPromote(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > maxCount {
            paths = Array(paths.prefix(maxCount))
        }
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func remove(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        UserDefaults.standard.set(paths, forKey: key)
    }
}
