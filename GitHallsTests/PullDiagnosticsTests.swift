//
//  PullDiagnosticsTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct PullDiagnosticsTests {
    /// Verbatim from git 2.50 on a dirty tree.
    private let refusal = """
    error: Your local changes to the following files would be overwritten by merge:
    \tGitHalls.App/MainWindow.xaml.cs
    Please commit your changes or stash them before you merge.
    Aborting
    """

    /// Verbatim from `git pull --autostash`, which exits 0 while saying this.
    private let autostashConflict = """
    Applying autostash resulted in conflicts.
    Your changes are safe in the stash.
    You can run "git stash pop" or "git stash drop" at any time.
    """

    @Test func recognisesThePullGitRefusedToStartOn() {
        #expect(PullDiagnostics.isBlockedByLocalChanges(refusal))
    }

    @Test func recognisesAnAutostashThatCouldNotBePutBack() {
        #expect(PullDiagnostics.autostashConflicted(autostashConflict))
    }

    @Test func doesNotConfuseTheTwo() {
        #expect(!PullDiagnostics.autostashConflicted(refusal))
        #expect(!PullDiagnostics.isBlockedByLocalChanges(autostashConflict))
    }

    @Test(arguments: [
        "",
        "fatal: Need to specify how to reconcile divergent branches.",
        "error: failed to push some refs",
        "Already up to date."
    ])
    func staysQuietAboutEveryOtherOutcome(message: String) {
        #expect(!PullDiagnostics.isBlockedByLocalChanges(message))
        #expect(!PullDiagnostics.autostashConflicted(message))
    }
}
