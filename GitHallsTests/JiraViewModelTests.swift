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

@MainActor
struct JiraViewModelEditTests {
    private func issue(_ key: String = "APP-1", status: String = "To Do") -> JiraIssue {
        JiraIssue(key: key, summary: "Old", status: status, statusCategory: "new",
                  type: "Task", priority: "Low", updated: Date(timeIntervalSince1970: 0))
    }

    /// A view model whose board holds `issues` and whose client talks to `mock`.
    private func model(_ mock: MockJira, issues: [JiraIssue]) -> JiraViewModel {
        let viewModel = JiraViewModel()
        let client = mock.client
        viewModel.clientFactory = { client }
        viewModel.groups = JiraIssueGrouping.byStatus(issues)
        return viewModel
    }

    @Test func successfulEditKeepsTheOptimisticCard() async {
        let mock = MockJira { _ in MockReply(status: 204) }
        let viewModel = model(mock, issues: [issue()])

        let ok = await viewModel.setSummary(issue(), "New")

        #expect(ok)
        #expect(viewModel.boardIssue(for: "APP-1")?.summary == "New")
        #expect(viewModel.actionFailed == false)
        #expect(mock.requests.first?.fields?["summary"] as? String == "New")
    }

    @Test func failedEditRollsTheCardBack() async {
        let mock = MockJira { _ in MockReply(status: 400, json: #"{"errorMessages":["Nope"]}"#) }
        let viewModel = model(mock, issues: [issue()])

        let ok = await viewModel.setPriority(issue(), JiraFieldOption(id: "1", label: "Highest"))

        #expect(ok == false)
        #expect(viewModel.boardIssue(for: "APP-1")?.priority == "Low")
        #expect(viewModel.actionFailed)
        #expect(viewModel.actionMessage == "Nope")
        #expect(viewModel.busyIssues.isEmpty)
    }

    @Test func rollbackOnlyTouchesTheFailedCard() async {
        let mock = MockJira { _ in MockReply(status: 500) }
        let viewModel = model(mock, issues: [issue("APP-1"), issue("APP-2")])

        _ = await viewModel.setLabels(issue("APP-1"), ["x"])

        #expect(viewModel.boardIssue(for: "APP-1")?.labels == [])
        #expect(viewModel.boardIssue(for: "APP-2") == issue("APP-2"))
    }

    @Test func storyPointsLooksUpTheFieldOnceThenEdits() async {
        let mock = MockJira { sent in
            sent.path == "/rest/api/3/field"
                ? MockReply(json: #"[{"id":"customfield_10016","name":"Story Points","custom":true,"schema":{"type":"number"}}]"#)
                : MockReply(status: 204)
        }
        let viewModel = model(mock, issues: [issue()])

        #expect(await viewModel.setStoryPoints(issue(), 8))
        #expect(await viewModel.setStoryPoints(issue(), 13))

        #expect(mock.requests.filter { $0.path == "/rest/api/3/field" }.count == 1)
        #expect(mock.requests.last?.fields?["customfield_10016"] as? Double == 13)
        #expect(viewModel.boardIssue(for: "APP-1")?.storyPoints == 13)
    }

    @Test func createAnswersTheKeyAndAsksTheBoardToReload() async {
        let mock = MockJira { _ in MockReply(status: 201, json: #"{"key":"APP-9"}"#) }
        let viewModel = model(mock, issues: [])
        let before = viewModel.reloadToken

        let key = await viewModel.create(JiraNewIssue(projectKey: "APP", issueTypeID: "10", summary: "New"))

        #expect(key == "APP-9")
        #expect(viewModel.reloadToken != before)
        #expect(viewModel.actionMessage == "APP-9 created.")
    }

    @Test func failedCreateReportsAndReturnsNil() async {
        let mock = MockJira { _ in MockReply(status: 400, json: #"{"errorMessages":["Bad type"]}"#) }
        let viewModel = model(mock, issues: [])

        let key = await viewModel.create(JiraNewIssue(projectKey: "APP", issueTypeID: "10", summary: "x"))

        #expect(key == nil)
        #expect(viewModel.actionFailed)
    }

    @Test func missingCredentialsFailWithoutTouchingTheBoard() async {
        let viewModel = JiraViewModel()
        viewModel.clientFactory = { nil }
        viewModel.groups = JiraIssueGrouping.byStatus([issue()])

        #expect(await viewModel.setSummary(issue(), "New") == false)
        #expect(viewModel.boardIssue(for: "APP-1")?.summary == "Old")
    }
}
