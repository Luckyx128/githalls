//
//  ClonePreferences.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 31/08/26.
//

import Foundation

enum ClonePreferences {
    private static let folderKey = "cloneDestinationFolder"

    static var defaultFolder: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: folderKey) {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Developer")
        }
        set { UserDefaults.standard.set(newValue.path, forKey: folderKey) }
    }
}
