//
//  BranchSyncTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct BranchSyncTests {
    @Test(arguments: [
        (false, 0, 0, SyncAction.publish),
        (false, 3, 0, SyncAction.publish),
        (true, 0, 0, SyncAction.upToDate),
        (true, 2, 0, SyncAction.push),
        (true, 0, 2, SyncAction.pull),
        (true, 1, 1, SyncAction.pullThenPush),
        (true, 5, 3, SyncAction.pullThenPush)
    ])
    func picksTheActionGitWouldAccept(hasUpstream: Bool, ahead: Int, behind: Int, expected: SyncAction) {
        #expect(BranchSync.action(hasUpstream: hasUpstream, ahead: ahead, behind: behind) == expected)
    }
}
