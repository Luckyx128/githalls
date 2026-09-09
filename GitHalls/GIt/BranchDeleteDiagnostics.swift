//
//  BranchDeleteDiagnostics.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation

/// Reading what git said about a branch delete, for the one refusal that is an
/// offer rather than a failure.
enum BranchDeleteDiagnostics {
    /// git refused `branch -d`: the branch holds commits no other branch does,
    /// so deleting it would strand them. Recoverable — the user may well want it
    /// gone anyway — but only by saying what is at stake first.
    ///
    /// Lowercased because older git capitalises "The branch" and current git
    /// does not.
    static func isUnmerged(_ message: String) -> Bool {
        message.lowercased().contains("not fully merged")
    }
}
