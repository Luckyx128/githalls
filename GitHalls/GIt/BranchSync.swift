//
//  BranchSync.swift
//  GitHalls
//

import Foundation

/// The one thing the sync button does, given how the branch sits against its
/// upstream.
enum SyncAction {
    case upToDate
    case publish
    case push
    case pull

    /// Ahead and behind at once. Its own action because git refuses a
    /// non-fast-forward push: the remote work has to come down first.
    case pullThenPush
}

enum BranchSync {
    /// Picks the action for an ahead/behind pair.
    ///
    /// Diverged is not "push, and let it fail". Preferring push there — which is
    /// what this did before — meant a button labelled "Push (1)" whose only
    /// possible outcome was a rejection.
    static func action(hasUpstream: Bool, ahead: Int, behind: Int) -> SyncAction {
        guard hasUpstream else { return .publish }
        if ahead > 0 && behind > 0 { return .pullThenPush }
        if ahead > 0 { return .push }
        if behind > 0 { return .pull }
        return .upToDate
    }
}
