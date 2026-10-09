//
//  PullRequestFlowTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct PullRequestFlowTests {
    private func pr(_ number: Int, into base: String, _ state: PullRequestStatus.State, approved: Bool = false) -> PullRequestStatus {
        PullRequestStatus(number: number, title: "t", url: "https://github.com/o/r/pull/\(number)", state: state,
                          baseRefName: base, reviewDecision: approved ? "APPROVED" : "REVIEW_REQUIRED")
    }

    private func move(_ id: String, to status: String, _ category: String = "indeterminate") -> JiraTransition {
        JiraTransition(id: id, name: status, toStatus: status, toStatusCategory: category, hasScreen: false, toStatusID: nil)
    }

    private var moves: [JiraTransition] {
        [move("1", to: "Code Review"), move("2", to: "Em Homologação"),
         move("3", to: "Pronto para Produção"), move("4", to: "Concluído", "done"), move("5", to: "Cancelado", "done")]
    }

    private var teamRules: [PullRequestRule] {
        [
            PullRequestRule(base: "*", event: .opened, status: ""),
            PullRequestRule(base: "dev", event: .merged, status: "Em Homologação"),
            PullRequestRule(base: "origin/homologacao", event: .merged, status: "Pronto para Produção"),
            PullRequestRule(base: "default", event: .merged, status: "")
        ]
    }

    private func offer(_ prs: [PullRequestStatus], rules: [PullRequestRule], status: String = "Em andamento",
                       category: String = "indeterminate", justOpened: Bool = false) -> String? {
        PullRequestFlow.move(pullRequests: prs, rules: rules, defaultBranch: "main", transitions: moves,
                             currentStatus: status, currentCategory: category,
                             includeAutomaticOpened: justOpened)?.transition.toStatus
    }

    @Test func devMergedHomPendingWithSafeDefaultsOffersNothing() {
        let prs = [pr(2, into: "homologacao", .open, approved: true), pr(1, into: "dev", .merged)]
        #expect(offer(prs, rules: PullRequestFlowStore.safeDefaults) == nil)
    }

    @Test func devMergedHomPendingWithTeamRulesOffersHomologation() {
        let prs = [pr(2, into: "homologacao", .open), pr(1, into: "dev", .merged)]
        #expect(offer(prs, rules: teamRules) == "Em Homologação")
    }

    @Test func homMergedGoesFurtherThanDev() {
        let prs = [pr(2, into: "homologacao", .merged), pr(1, into: "dev", .merged)]
        #expect(offer(prs, rules: teamRules) == "Pronto para Produção")
    }

    @Test func neverOffersAStageTheIssueIsAlreadyPast() {
        let prs = [pr(2, into: "homologacao", .open), pr(1, into: "dev", .merged)]
        #expect(offer(prs, rules: teamRules, status: "Em Homologação") == nil)
        #expect(offer(prs, rules: teamRules, status: "Pronto para Produção") == nil)
    }

    @Test func mergeIntoTheDefaultBranchOffersDoneNotCancelled() {
        #expect(offer([pr(3, into: "main", .merged)], rules: PullRequestFlowStore.safeDefaults) == "Concluído")
        #expect(offer([pr(3, into: "main", .merged)], rules: teamRules, status: "Concluído", category: "done") == nil)
    }

    @Test func automaticReviewOnlyRightAfterOpening() {
        let open = [pr(1, into: "dev", .open)]
        #expect(offer(open, rules: PullRequestFlowStore.safeDefaults) == nil)
        #expect(offer(open, rules: PullRequestFlowStore.safeDefaults, justOpened: true) == "Code Review")
    }

    @Test func approvalCountsWhenTheTableSaysSo() {
        let rules = [PullRequestRule(base: "homologacao", event: .approved, status: "Em Homologação")]
        #expect(offer([pr(2, into: "homologacao", .open)], rules: rules) == nil)
        #expect(offer([pr(2, into: "homologacao", .open, approved: true)], rules: rules) == "Em Homologação")
    }

    @Test func closedPullRequestsReachNothing() {
        #expect(offer([pr(1, into: "dev", .closed)], rules: teamRules) == nil)
    }

    @Test func oneLinePerBaseWithTheNewestPullRequest() {
        let prs = [pr(41, into: "dev", .merged), pr(48, into: "homologacao", .open, approved: true),
                   pr(30, into: "dev", .merged), pr(12, into: "dev", .closed), pr(50, into: "main", .merged)]

        let latest = PullRequestFlow.latestPerBase(prs)

        #expect(latest.map(\.pullRequest.number) == [50, 48, 41])
        #expect(latest.map(\.earlier) == [0, 0, 2])
    }

    @Test func branchNamesCompareWithoutRemoteOrCase() {
        #expect(PullRequestFlow.normalize("origin/Homologacao") == "homologacao")
        #expect(PullRequestFlow.normalize("refs/heads/dev") == "dev")
        #expect(PullRequestFlow.matches("origin/homologacao", base: "homologacao", defaultBranch: nil))
        #expect(PullRequestFlow.matches("default", base: "master", defaultBranch: "origin/master"))
        #expect(!PullRequestFlow.matches("default", base: "dev", defaultBranch: nil))
        #expect(PullRequestFlow.matches("*", base: "anything", defaultBranch: nil))
    }

    @Test func decodesWhatGhPrints() throws {
        let json = #"""
        [{"number":7,"title":"x","url":"u","state":"OPEN","baseRefName":"homologacao","reviewDecision":"APPROVED"},
         {"number":6,"title":"y","url":"v","state":"MERGED","baseRefName":"dev","reviewDecision":""}]
        """#
        let prs = try JSONDecoder().decode([PullRequestStatus].self, from: Data(json.utf8))
        #expect(prs[0].isApproved && prs[0].baseRefName == "homologacao")
        #expect(!prs[1].isApproved && prs[1].state == .merged)
    }

    @Test func rulesRoundTripThroughSettings() throws {
        let rules = teamRules
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode([PullRequestRule].self, from: data) == rules)
    }
}
