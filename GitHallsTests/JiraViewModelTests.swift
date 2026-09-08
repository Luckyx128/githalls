//
//  JiraViewModelTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraViewModelTests {

    /// The view model only forwards now; the naming itself is pinned by
    /// JiraBranchNameTests. This keeps the seam covered.
    @MainActor
    @Test func suggestedBranchNameNamesTheTypeAndTheKey() {
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
        #expect(viewModel.suggestedBranchName(for: issue) == "fix-PROJ-123")
    }
}
