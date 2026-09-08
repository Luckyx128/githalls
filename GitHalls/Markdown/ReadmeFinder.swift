//
//  ReadmeFinder.swift
//  GitHalls
//

import Foundation

/// Which file in a repository's root is its README.
///
/// The name is a convention, not a rule: it comes in several spellings and any
/// casing. Picking is kept apart from reading so it can be tested without a
/// repository on disk.
enum ReadmeFinder {
    /// Best first. A repository carrying both README.md and README.txt means
    /// the markdown one, which is what every forge shows.
    private static let preferredExtensions = ["md", "markdown", "mdown", "rst", "txt", ""]

    static func pick(from fileNames: [String]) -> String? {
        let candidates = fileNames.filter { name in
            let base = (name as NSString).deletingPathExtension

            return base.caseInsensitiveCompare("readme") == .orderedSame
        }

        guard !candidates.isEmpty else { return nil }

        return candidates.min { lhs, rhs in
            rank(lhs) != rank(rhs) ? rank(lhs) < rank(rhs) : lhs < rhs
        }
    }

    private static func rank(_ name: String) -> Int {
        let ext = (name as NSString).pathExtension.lowercased()

        return preferredExtensions.firstIndex(of: ext) ?? preferredExtensions.count
    }
}
