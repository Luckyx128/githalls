//
//  JiraIssueKey.swift
//  GitHalls
//

import Foundation

/// Issue keys found in free text — branch names, commit subjects — the same way
/// Jira's development panel finds them: "feature/sweb-6851-pdf" belongs to
/// SWEB-6851. Case is ignored because branch names are usually lower case.
///
/// A match is only a candidate. "release-2" reads like a key too; whoever acts
/// on one asks Jira first, and a key Jira does not know links nothing.
nonisolated enum JiraIssueKey {
    /// The first key in `text`, upper-cased.
    static func find(in text: String) -> String? {
        all(in: text).first
    }

    /// Every key in `text`, upper-cased, in order, without repeats.
    static func all(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return pattern.matches(in: text, range: range).compactMap { match in
            guard let found = Range(match.range(at: 1), in: text) else { return nil }
            let key = text[found].uppercased()
            return seen.insert(key).inserted ? key : nil
        }
    }

    /// A project key is a letter followed by letters, digits or underscores; the
    /// number follows a hyphen. Neither side may run on into more of the same.
    private static let pattern = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9_])([A-Za-z][A-Za-z0-9_]+-[0-9]+)(?![0-9])"
    )

    /// Whether `text` already names `key`, in any case.
    static func mentions(_ key: String, in text: String) -> Bool {
        all(in: text).contains(key.uppercased())
    }

    /// "SWEB" from "SWEB-6851".
    static func project(of key: String) -> String {
        String(key.split(separator: "-").first ?? Substring(key))
    }
}
