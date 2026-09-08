//
//  JiraBranchNameTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraBranchNameTests {
    private func issue(key: String, type: String, summary: String = "Anything at all") -> JiraIssue {
        JiraIssue(key: key, summary: summary, status: "To Do", statusCategory: "new",
                  type: type, priority: nil, updated: Date())
    }

    @Test(arguments: [
        ("Bug", "SWEB-12903", "fix-SWEB-12903"),
        ("Story", "SWEB-12903", "feature-SWEB-12903"),
        ("Task", "SWEB-12903", "chore-SWEB-12903")
    ])
    func namesTheBranchAfterTheTypeAndTheKey(type: String, key: String, expected: String) {
        #expect(JiraBranchName.suggest(for: issue(key: key, type: type)) == expected)
    }

    @Test func keepsTheKeyExactlyAsJiraSpellsIt() {
        #expect(JiraBranchName.suggest(key: "SWEB-12903", jiraType: "Story") == "feature-SWEB-12903")
    }

    @Test func dropsTheSummaryEntirely() {
        let long = issue(key: "ABC-1", type: "Task",
                         summary: "A summary long enough to have been a slug before")
        #expect(JiraBranchName.suggest(for: long) == "chore-ABC-1")
    }

    @Test(arguments: ["Spike", ""])
    func usesFeatureForAnIssueTypeItDoesNotKnow(type: String) {
        #expect(JiraBranchName.suggest(key: "ABC-9", jiraType: type) == "feature-ABC-9")
    }

    @Test func usesFeatureWhenThereIsNoTypeAtAll() {
        #expect(JiraBranchName.suggest(key: "ABC-9", jiraType: nil) == "feature-ABC-9")
    }

    @Test func collapsesWhatGitWouldRefuseInAKey() {
        #expect(JiraBranchName.suggest(key: "  ABC 9  ", jiraType: "Story") == "feature-ABC-9")
    }

    @Test func fallsBackToTheTypeAloneWhenNothingSurvivesTheKey() {
        #expect(JiraBranchName.suggest(key: "~~~", jiraType: "Bug") == "fix")
    }
}

struct JiraBranchTypeTests {
    @Test(arguments: [
        ("Bug", "fix"), ("Defect", "fix"),
        ("Story", "feature"), ("Epic", "feature"), ("New Feature", "feature"), ("Improvement", "feature"),
        ("Task", "chore"), ("Sub-task", "chore")
    ])
    func mapsTheEnglishTypesJiraShipsWith(type: String, expected: String) {
        #expect(JiraBranchType.of(type) == expected)
    }

    @Test(arguments: [
        ("Erro", "fix"), ("Defeito", "fix"),
        ("História", "feature"), ("Épico", "feature"), ("Melhoria", "feature"),
        ("Nova Funcionalidade", "feature"),
        ("Tarefa", "chore"), ("Subtarefa", "chore")
    ])
    func mapsThePortugueseNamesTheProjectActuallyUses(type: String, expected: String) {
        #expect(JiraBranchType.of(type) == expected)
    }

    @Test(arguments: ["BUG", "bug", "  Bug  "])
    func ignoresCaseAndSurroundingSpace(type: String) {
        #expect(JiraBranchType.of(type) == "fix")
    }

    @Test(arguments: [("HISTÓRIA", "feature"), ("historia", "feature"), ("Manutenção", "chore")])
    func ignoresAccents(type: String, expected: String) {
        #expect(JiraBranchType.of(type) == expected)
    }

    @Test(arguments: [
        ("Bug de Produção", "fix"),
        ("Story - Frontend", "feature"),
        ("Tarefa técnica", "chore")
    ])
    func readsACompoundTypeByItsWords(type: String, expected: String) {
        #expect(JiraBranchType.of(type) == expected)
    }

    @Test func readsWordsAndNotSubstrings() {
        // "Debug tooling" contains "bug" and is not a bug.
        #expect(JiraBranchType.of("Debug tooling") == "feature")
    }

    @Test(arguments: ["Spike", "", "   "])
    func fallsBackToFeatureForATypeItDoesNotKnow(type: String) {
        #expect(JiraBranchType.of(type) == "feature")
    }
}
