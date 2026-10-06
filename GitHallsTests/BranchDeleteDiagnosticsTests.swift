//
//  BranchDeleteDiagnosticsTests.swift
//  GitHallsTests
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import Testing
@testable import GitHalls

struct BranchDeleteDiagnosticsTests {

    @Test func currentGitWording() {
        let message = """
        error: the branch 'feature' is not fully merged.
        hint: If you are sure you want to delete it, run 'git branch -D feature'.
        """

        #expect(BranchDeleteDiagnostics.isUnmerged(message))
    }

    @Test func olderGitCapitalisation() {
        #expect(BranchDeleteDiagnostics.isUnmerged("error: The branch 'feature' is not fully merged."))
    }

    @Test func unrelatedFailuresAreNotAnOffer() {
        #expect(BranchDeleteDiagnostics.isUnmerged("error: branch 'feature' not found.") == false)
        #expect(BranchDeleteDiagnostics.isUnmerged("error: Cannot delete branch 'main' checked out at '/tmp/repo'") == false)
        #expect(BranchDeleteDiagnostics.isUnmerged("") == false)
    }

    @Test func remoteBranchAlreadyGone() {
        let message = """
        error: unable to delete 'feature': remote ref does not exist
        error: failed to push some refs to 'https://github.com/org/repo.git'
        """
        #expect(BranchDeleteDiagnostics.isMissingOnRemote(message))
        #expect(BranchDeleteDiagnostics.isMissingOnRemote("error: failed to push some refs") == false)
    }
}
