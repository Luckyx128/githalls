//
//  BranchCreatorTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct BranchCreatorTests {
    @Test func takesTheFirstLineOfTheOldestFirstLog() {
        #expect(BranchCreator.firstAuthor(fromLog: "Ana Souza\nBob\nBob\n") == "Ana Souza")
    }

    @Test(arguments: ["", "\n", "  \n"])
    func namesNobodyWhenTheBranchHasNothingOfItsOwn(raw: String) {
        #expect(BranchCreator.firstAuthor(fromLog: raw) == nil)
    }

    @Test func parsesTipsAndSkipsTheRemoteHeadPointer() {
        let raw = """
        aaa refs/heads/main
        bbb refs/heads/feature/x y
        ccc refs/remotes/origin/HEAD
        ddd refs/remotes/origin/main
        """
        let tips = BranchCreator.parseTips(raw)
        #expect(tips == [
            "refs/heads/main": "aaa",
            "refs/heads/feature/x y": "bbb",
            "refs/remotes/origin/main": "ddd"
        ])
    }

    @Test func buildsFullRefNames() {
        #expect(BranchCreator.ref(for: Branch(name: "a/b", isCurrent: false, isRemote: false)) == "refs/heads/a/b")
        #expect(BranchCreator.ref(for: Branch(name: "origin/a", isCurrent: false, isRemote: true)) == "refs/remotes/origin/a")
    }

    @Test func showsYouForTheCurrentIdentity() {
        #expect(BranchCreator.label(for: "Lucas", currentUser: "lucas") == "you")
        #expect(BranchCreator.label(for: "Ana", currentUser: "Lucas") == "Ana")
        #expect(BranchCreator.label(for: "Ana", currentUser: nil) == "Ana")
    }
}
