//
//  PullDiagnostics.swift
//  GitHalls
//

import Foundation

/// Reading what git said about a pull, for the two cases the exit code does not
/// tell apart on its own.
enum PullDiagnostics {
    /// git refused the pull: merging would have written over work in progress.
    /// Recoverable without losing anything — the changes can be set aside for
    /// the pull and put back after.
    static func isBlockedByLocalChanges(_ message: String) -> Bool {
        let lowered = message.lowercased()

        return lowered.contains("would be overwritten by merge")
            || lowered.contains("please commit your changes or stash them")
    }

    /// The pull landed, and putting the local changes back conflicted.
    ///
    /// git exits 0 here and says this only on stderr, so a caller that reads
    /// the exit code alone reports plain success and leaves the user in a
    /// conflicted tree with a stash they were never told about.
    static func autostashConflicted(_ message: String) -> Bool {
        message.lowercased().contains("applying autostash resulted in conflicts")
    }
}
