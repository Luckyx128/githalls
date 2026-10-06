//
//  AutoFetch.swift
//  GitHalls
//

import Foundation

/// When a background fetch is worth running, and how its age reads.
enum AutoFetch {
    /// UserDefaults key behind the "Fetch automatically" setting.
    static let enabledKey = "autoFetchEnabled"

    /// Timer cadence. Frequent enough that "behind" stays honest, rare enough
    /// that a remote is never hammered.
    static let interval: Duration = .seconds(300)

    /// Activating the window fetches only if the last one is older than this:
    /// alt-tabbing back and forth must not become a fetch per switch.
    static let activationMinimumAge: TimeInterval = 60

    static func isDue(lastFetch: Date?, now: Date = .now, minimumAge: TimeInterval) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= minimumAge
    }

    /// "Fetched just now", "Fetched 5 min ago", "Fetched 2 h ago".
    static func ageLabel(lastFetch: Date?, now: Date = .now) -> String {
        guard let lastFetch else { return "Not fetched yet" }
        let seconds = max(0, now.timeIntervalSince(lastFetch))
        switch seconds {
        case ..<60: return "Fetched just now"
        case ..<3600: return "Fetched \(Int(seconds / 60)) min ago"
        case ..<86_400: return "Fetched \(Int(seconds / 3600)) h ago"
        default: return "Fetched \(Int(seconds / 86_400)) d ago"
        }
    }
}
