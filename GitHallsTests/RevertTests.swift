//
//  RevertTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct RevertTests {
    @Test func ordinaryCommitReverts() {
        #expect(GitService.revertArguments(hash: "abc", parentCount: 1) == ["revert", "--no-edit", "abc"])
    }

    @Test func mergeCommitNeedsAMainline() {
        #expect(GitService.revertArguments(hash: "abc", parentCount: 2) == ["revert", "--no-edit", "-m", "1", "abc"])
    }

    @Test func revertStateIsDistinctFromMerge() {
        let state = MergeState(operation: .revert, unresolvedPaths: [], markerPaths: [], preparedMessage: nil)
        #expect(state.operation.abortTitle == "Abort Revert")
        #expect(MergeState.Operation.merge.abortTitle == "Abort Merge")
    }
}
