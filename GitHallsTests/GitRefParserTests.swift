//
//  GitRefParserTests.swift
//  GitHallsTests
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import Testing
@testable import GitHalls

struct GitRefParserTests {

    @Test func attachedHeadWithLocalAndRemote() {
        // The real decoration this repository produces on its own HEAD.
        let refs = GitRefParser.parse(
            "HEAD -> refs/heads/main, refs/remotes/origin/main, refs/remotes/origin/HEAD"
        )

        // Three, not four: origin/HEAD is a symbolic alias and would put a
        // second chip on a commit that already says origin/main.
        #expect(refs.count == 3)
        #expect(refs[0] == GitRef(kind: .head, name: "HEAD", isHeadTarget: false))
        #expect(refs[1] == GitRef(kind: .localBranch, name: "main", isHeadTarget: true))
        #expect(refs[2] == GitRef(kind: .remoteBranch, name: "origin/main", isHeadTarget: false))
    }

    @Test func detachedHead() {
        let refs = GitRefParser.parse("HEAD")

        #expect(refs.count == 1)
        #expect(refs[0].kind == .head)
        #expect(refs.contains { $0.kind == .localBranch } == false)
    }

    @Test func tag() {
        let refs = GitRefParser.parse("tag: refs/tags/v0.1.1")

        #expect(refs.count == 1)
        #expect(refs[0].kind == .tag)
        #expect(refs[0].name == "v0.1.1")
    }

    @Test func emptyDecoration() {
        #expect(GitRefParser.parse("").isEmpty)
        #expect(GitRefParser.parse("   ").isEmpty)
    }

    @Test func refsWeCannotActOn() {
        #expect(GitRefParser.parse("refs/notes/commits").isEmpty)
        #expect(GitRefParser.parse("refs/stash").isEmpty)
        #expect(GitRefParser.parse("refs/pull/12/head").isEmpty)
    }

    /// The whole reason for --decorate=full: with git's short decoration this
    /// local branch is spelled exactly like the remote-tracking ref.
    @Test func localBranchNamedLikeARemote() {
        let refs = GitRefParser.parse("refs/heads/origin/main")

        #expect(refs.count == 1)
        #expect(refs[0].kind == .localBranch)
        #expect(refs[0].name == "origin/main")
    }

    @Test func tagNamedLikeABranch() {
        let refs = GitRefParser.parse("refs/heads/main, tag: refs/tags/main")

        #expect(refs.count == 2)
        #expect(refs.filter { $0.kind == .localBranch }.count == 1)
        #expect(refs.filter { $0.kind == .tag }.count == 1)
    }

    @Test func orderIsStableAndKindSorted() {
        let refs = GitRefParser.parse(
            "tag: refs/tags/v2, refs/remotes/origin/main, refs/heads/zeta, refs/heads/alpha"
        )

        #expect(refs.map(\.kind) == [.localBranch, .localBranch, .remoteBranch, .tag])
        #expect(refs.map(\.name) == ["alpha", "zeta", "origin/main", "v2"])
        #expect(GitRefParser.parse("refs/heads/b, refs/heads/a") == GitRefParser.parse("refs/heads/a, refs/heads/b"))
    }

    @Test func headTargetIsOnlyTheAttachedBranch() {
        // main is where HEAD points; other-branch merely sits on the same commit.
        let refs = GitRefParser.parse("HEAD -> refs/heads/main, refs/heads/other-branch")
        let locals = refs.filter { $0.kind == .localBranch }

        #expect(locals.first { $0.name == "main" }?.isHeadTarget == true)
        #expect(locals.first { $0.name == "other-branch" }?.isHeadTarget == false)
    }
}
