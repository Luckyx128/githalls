//
//  IssueLinkTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraIssueKeyTests {
    @Test func findsTheKeyInBranchNames() {
        #expect(JiraIssueKey.find(in: "feature/sweb-6851-pdf") == "SWEB-6851")
        #expect(JiraIssueKey.find(in: "SWEB-6832-front-kanban-whats-message") == "SWEB-6832")
        #expect(JiraIssueKey.find(in: "fix/APP2-10") == "APP2-10")
        #expect(JiraIssueKey.find(in: "feature-sweb-12-x") == "SWEB-12")
    }

    @Test func ignoresNamesWithoutAKey() {
        #expect(JiraIssueKey.find(in: "main") == nil)
        #expect(JiraIssueKey.find(in: "feature/new-diff") == nil)
        #expect(JiraIssueKey.find(in: "x-") == nil)
        #expect(JiraIssueKey.find(in: "1A-2") == nil)
    }

    @Test func listsEachKeyOnceAndChecksMentions() {
        #expect(JiraIssueKey.all(in: "SWEB-1 and sweb-1, then APP-2") == ["SWEB-1", "APP-2"])
        #expect(JiraIssueKey.mentions("SWEB-1", in: "fix: thing (sweb-1)"))
        #expect(!JiraIssueKey.mentions("SWEB-1", in: "fix: SWEB-10"))
        #expect(JiraIssueKey.project(of: "SWEB-6851") == "SWEB")
    }
}

struct CommitIssueKeyTests {
    @Test func addsTheKeyAsATrailer() {
        let message = CommitMessageComposer.compose(summary: "feat: pdf", description: "", coAuthors: [], issueKeys: ["SWEB-1"])
        #expect(message.summary == "feat: pdf")
        #expect(message.body == "Refs: SWEB-1")

        let two = CommitMessageComposer.compose(summary: "feat: pdf (SWEB-1)", description: "", coAuthors: [], issueKeys: ["SWEB-1", "SWEB-2", "APP-3"])
        #expect(two.body == "Refs: SWEB-2, APP-3")
    }

    @Test func leavesAMessageThatAlreadyNamesIt() {
        let inSummary = CommitMessageComposer.compose(summary: "feat(sweb-1): pdf", description: "", coAuthors: [], issueKeys: ["SWEB-1"])
        #expect(inSummary.body == nil)

        let inBody = CommitMessageComposer.compose(summary: "feat: pdf", description: "Part of SWEB-1", coAuthors: [], issueKeys: ["SWEB-1"])
        #expect(inBody.body == "Part of SWEB-1")
    }

    @Test func noKeyNoTrailer() {
        #expect(CommitMessageComposer.compose(summary: "x", description: "", coAuthors: []).body == nil)
    }
}

struct IssueLinkRulesTests {
    private func commit(_ hash: String, _ summary: String) -> Commit {
        Commit(hash: hash + String(repeating: "0", count: 33), shortHash: hash, authorName: "Erik", date: .now, summary: summary)
    }

    private func transition(_ id: String, to status: String, category: String) -> JiraTransition {
        JiraTransition(id: id, name: status, toStatus: status, toStatusCategory: category, hasScreen: false, toStatusID: nil)
    }

    @Test func branchKeysClaimEveryCommit() {
        let keys = IssueLinkRules.keys(forBranch: "feature/SWEB-1-pdf", manual: ["sweb-2", "SWEB-1"])
        #expect(keys == ["SWEB-1", "SWEB-2"])

        let groups = IssueLinkRules.group([commit("a1", "fix: x"), commit("b2", "APP-9 other")], branchKeys: keys)
        #expect(groups.map(\.key) == ["SWEB-1", "SWEB-2"])
        #expect(groups.allSatisfy { $0.commits.count == 2 })
    }

    @Test func withoutABranchKeyCommitsSpeakForThemselves() {
        let groups = IssueLinkRules.group(
            [commit("a1", "SWEB-2: x"), commit("b2", "chore: bump"), commit("c3", "fix APP-9")],
            branchKeys: IssueLinkRules.keys(forBranch: "develop", manual: [])
        )
        #expect(groups.map(\.key) == ["SWEB-2", "APP-9"])
    }

    @Test func commentListsCommitsOldestFirstWithLinks() {
        let text = IssueLinkRules.comment(
            branch: "feature/SWEB-1",
            repository: "sigra_web",
            commits: [commit("b2", "feat: [WIP] logo"), commit("a1", "fix: margem")]
        ) { URL(string: "https://github.com/o/r/commit/\($0.hash)") }

        let lines = text.components(separatedBy: "\n")
        #expect(lines[0] == "**2 commits enviados para `feature/SWEB-1`** em sigra\\_web")
        #expect(lines[2].hasPrefix("- [`a1`](https://github.com/o/r/commit/a1"))
        #expect(lines[3].hasSuffix("feat: \\[WIP\\] logo"))
        #expect(lines.last == "_via GitHalls_")
    }

    @Test func commentRendersAsLinkedCode() {
        let text = IssueLinkRules.comment(branch: "b", repository: "r", commits: [commit("a1", "x")]) { _ in
            URL(string: "https://github.com/o/r/commit/a1")
        }
        let document = JiraMarkdownADF.document(from: text)
        let json = String(data: try! JSONSerialization.data(withJSONObject: document), encoding: .utf8)!
        #expect(json.contains(#""href":"https:\/\/github.com\/o\/r\/commit\/a1""#))
        #expect(json.contains(#""type":"code""#))
    }

    @Test func picksTheReviewMove() {
        let moves = [
            transition("1", to: "In Progress", category: "indeterminate"),
            transition("2", to: "Em Revisão", category: "indeterminate"),
            transition("3", to: "Done", category: "done")
        ]
        #expect(IssueLinkRules.reviewTransition(in: moves, currentStatus: "In Progress")?.id == "2")
        #expect(IssueLinkRules.reviewTransition(in: moves, currentStatus: "Code Review") == nil)
        #expect(IssueLinkRules.reviewTransition(in: [moves[0], moves[2]], currentStatus: "To Do") == nil)
    }

    @Test func picksDoneOverCancelled() {
        let moves = [
            transition("1", to: "Cancelado", category: "done"),
            transition("2", to: "Concluído", category: "done"),
            transition("3", to: "Em Revisão", category: "indeterminate")
        ]
        #expect(IssueLinkRules.doneTransition(in: moves, currentCategory: "indeterminate")?.id == "2")
        #expect(IssueLinkRules.doneTransition(in: [moves[0]], currentCategory: "indeterminate") == nil)
        #expect(IssueLinkRules.doneTransition(in: moves, currentCategory: "done") == nil)
    }

    @Test func commitURLOnlyForGitHub() {
        #expect(IssueLinkRules.commitURL(remote: "git@github.com:ambiensys/sigra.git", hash: "abc")?.absoluteString
                == "https://github.com/ambiensys/sigra/commit/abc")
        #expect(IssueLinkRules.commitURL(remote: nil, hash: "abc") == nil)
    }

    @Test func handLinksArePerRepositoryAndBranch() {
        let defaults = UserDefaults(suiteName: "IssueLinkTests-\(UUID().uuidString)")!
        let web = URL(fileURLWithPath: "/repos/sigra_web")
        let api = URL(fileURLWithPath: "/repos/sigra_api")

        BranchLinkStore.link("sweb-1", repository: web, branch: "develop", defaults: defaults)
        BranchLinkStore.link("SWEB-2", repository: web, branch: "develop", defaults: defaults)
        BranchLinkStore.link("SWEB-1", repository: web, branch: "develop", defaults: defaults)
        BranchLinkStore.link("SWEB-1", repository: api, branch: "feature/x", defaults: defaults)

        #expect(BranchLinkStore.keys(repository: web, branch: "develop", defaults: defaults) == ["SWEB-1", "SWEB-2"])
        #expect(BranchLinkStore.keys(repository: api, branch: "develop", defaults: defaults).isEmpty)
        #expect(BranchLinkStore.branches(linkedTo: "SWEB-1", repository: web, defaults: defaults) == ["develop"])
        #expect(BranchLinkStore.linkedKeys(repository: web, defaults: defaults) == ["SWEB-1", "SWEB-2"])

        BranchLinkStore.unlink("SWEB-1", repository: web, branch: "develop", defaults: defaults)
        BranchLinkStore.unlink("SWEB-2", repository: web, branch: "develop", defaults: defaults)
        #expect(BranchLinkStore.keys(repository: web, branch: "develop", defaults: defaults).isEmpty)
        #expect(BranchLinkStore.branches(linkedTo: "SWEB-1", repository: api, defaults: defaults) == ["feature/x"])
    }

    @Test func postedCommitsAreRememberedPerIssue() {
        let defaults = UserDefaults(suiteName: "IssueLinkTests-\(UUID().uuidString)")!
        PostedCommitsStore.record(["a", "b"], on: "SWEB-1", defaults: defaults)
        PostedCommitsStore.record(["b", "c"], on: "SWEB-1", defaults: defaults)
        #expect(PostedCommitsStore.posted(on: "SWEB-1", defaults: defaults) == ["a", "b", "c"])
        #expect(PostedCommitsStore.posted(on: "APP-1", defaults: defaults).isEmpty)
    }
}
