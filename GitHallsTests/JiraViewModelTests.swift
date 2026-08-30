//
//  JiraViewModelTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraViewModelTests {

    @MainActor
    @Test func suggestedBranchNameSlugifiesSummary() {
        let viewModel = JiraViewModel()
        let issue = JiraIssue(
            key: "PROJ-123",
            summary: "Fix login page crash!",
            status: "To Do",
            statusCategory: "new",
            type: "Bug",
            priority: "High",
            updated: Date()
        )
        #expect(viewModel.suggestedBranchName(for: issue) == "PROJ-123-fix-login-page-crash")
    }

    @MainActor
    @Test func suggestedBranchNameFallsBackToKeyWhenSummaryHasNoAlphanumerics() {
        let viewModel = JiraViewModel()
        let issue = JiraIssue(
            key: "PROJ-9",
            summary: "!!!",
            status: "To Do",
            statusCategory: "new",
            type: "Task",
            priority: nil,
            updated: Date()
        )
        #expect(viewModel.suggestedBranchName(for: issue) == "PROJ-9")
    }

    @MainActor
    @Test func suggestedBranchNameTruncatesLongSummary() {
        let viewModel = JiraViewModel()
        let longSummary = String(repeating: "word ", count: 20)
        let issue = JiraIssue(
            key: "PROJ-1",
            summary: longSummary,
            status: "To Do",
            statusCategory: "new",
            type: "Task",
            priority: nil,
            updated: Date()
        )
        let result = viewModel.suggestedBranchName(for: issue)
        #expect(result.hasPrefix("PROJ-1-"))
        #expect(result.count <= "PROJ-1-".count + 40)
    }
}
