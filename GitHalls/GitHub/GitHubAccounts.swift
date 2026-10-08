//
//  GitHubAccounts.swift
//  GitHalls
//

import Foundation

/// Pure helpers for juggling several `gh` logins. Kept free of Process and
/// UserDefaults so they can be tested with captured `gh` output.
enum GitHubAccounts {
    /// Logins on github.com, in the order `gh` lists them. Prefers the JSON
    /// from `gh auth status --json hosts` (gh 2.4x+) and falls back to
    /// scraping the human output for older versions.
    static func logins(fromStatusOutput output: String) -> [String] {
        let fromJSON = logins(fromJSON: output)
        return fromJSON.isEmpty ? logins(fromText: output) : fromJSON
    }

    static func logins(fromJSON json: String) -> [String] {
        struct Status: Decodable {
            struct Entry: Decodable {
                let login: String
                let state: String?
            }
            let hosts: [String: [Entry]]
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: Data(json.utf8)),
              let entries = status.hosts["github.com"] else { return [] }
        return unique(entries.filter { $0.state == nil || $0.state == "success" }.map(\.login))
    }

    /// Reads lines like "✓ Logged in to github.com account Luckyx128 (keyring)".
    static func logins(fromText text: String) -> [String] {
        let marker = "Logged in to github.com account "
        var found: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: marker) else { continue }
            if let login = line[range.upperBound...].split(separator: " ").first {
                found.append(String(login))
            }
        }
        return unique(found)
    }

    /// Whether `gh` failed because the logged-in account cannot see the
    /// repository, which another account might. GitHub answers 404 rather than
    /// 403 for private repos you cannot read, hence "Not Found".
    static func isAccessError(_ message: String) -> Bool {
        let needles = [
            "could not resolve to a repository",
            "http 404",
            "not found",
            "resource not accessible"
        ]
        let lowered = message.lowercased()
        return needles.contains { lowered.contains($0) }
    }

    /// Order to try accounts in: the remembered one first, then the active
    /// default (`nil`, i.e. no token override), then every other login.
    static func attemptOrder(logins: [String], remembered: String?) -> [String?] {
        var order: [String?] = []
        if let remembered, logins.contains(remembered) { order.append(remembered) }
        order.append(nil)
        order += logins.filter { $0 != remembered }.map { Optional($0) }
        return order
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
