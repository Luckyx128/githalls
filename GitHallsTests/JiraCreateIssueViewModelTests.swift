//
//  JiraCreateIssueViewModelTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

@MainActor
struct JiraCreateIssueViewModelTests {
    private func loaded(_ stub: StubJiraAuthoring = StubJiraAuthoring()) async -> JiraCreateIssueViewModel {
        let model = JiraCreateIssueViewModel(authoring: stub)
        await model.load()
        return model
    }

    @Test func loadPicksFirstProjectAndATaskType() async {
        let model = await loaded()
        #expect(model.selectedProject?.key == "DEMO")
        #expect(model.selectedType?.name == "Task")
    }

    @Test func summaryIsRequired() async {
        let model = await loaded()
        #expect(!model.canSubmit)
        #expect(model.missing == ["Summary"])
        model.summary = "Fix it"
        #expect(model.canSubmit)
    }

    @Test func requiredCustomFieldBlocksUntilFilled() async {
        var stub = StubJiraAuthoring()
        stub.fields = [JiraCreateField(key: "customfield_1", name: "Team", required: true, kind: .string)]
        let model = await loaded(stub)
        model.summary = "x"
        #expect(model.missing == ["Team"])

        model.extraValues["customfield_1"] = "Core"
        #expect(model.canSubmit)
        #expect(model.draft()?.extra == [.custom("customfield_1", .string("Core"))])
    }

    @Test func standardRequiredFieldsAreNotDynamic() async {
        var stub = StubJiraAuthoring()
        stub.fields = [JiraCreateField(key: "summary", name: "Summary", required: true, kind: .string),
                       JiraCreateField(key: "priority", name: "Priority", required: true, kind: .priority)]
        let model = await loaded(stub)
        #expect(model.dynamicFields.isEmpty)
    }

    @Test func draftCarriesFields() async {
        let model = await loaded()
        model.summary = "  Title "
        model.descriptionMarkdown = "**b**"
        model.labelsText = "a, b  c"
        model.priorityID = "2"
        model.assignee = JiraUser(accountID: "u1", displayName: "U")
        let draft = model.draft()
        #expect(draft?.summary == "Title")
        #expect(draft?.labels == ["a", "b", "c"])
        #expect(draft?.assigneeAccountID == "u1")
        #expect(draft?.priorityID == "2")
        #expect(draft?.description == "**b**")
    }

    @Test func subtaskNeedsParent() async {
        let model = await loaded()
        await model.select(type: model.issueTypes.first { $0.isSubtask })
        model.summary = "x"
        #expect(model.missing == ["Parent"])
        model.parentKey = "DEMO-1"
        #expect(model.canSubmit)
    }

    @Test func submitReturnsKeyOrReportsError() async {
        let model = await loaded()
        model.summary = "x"
        #expect(await model.submit() == "DEMO-1")

        var failing = StubJiraAuthoring()
        failing.failure = JiraError.unauthorized
        let bad = await loaded(failing)
        bad.summary = "x"
        #expect(await bad.submit() == nil)
        #expect(bad.errorMessage != nil)
    }

    @Test func quickCreateDerivesProjectKey() {
        #expect(JiraQuickCreate.projectKey(from: ["ABC-12", "ABC-3"]) == "ABC")
        #expect(JiraQuickCreate.projectKey(from: ["MY-PROJ-4"]) == "MY-PROJ")
        #expect(JiraQuickCreate.projectKey(from: []) == nil)
    }
}

@MainActor
struct JiraQuickCreateBoardTests {
    private func transition(_ id: String, to status: String, statusID: String) -> JiraTransition {
        JiraTransition(id: id, name: id, toStatus: status, toStatusCategory: "indeterminate", toStatusID: statusID)
    }

    @Test func movesIntoACustomNamedColumnByStatusID() {
        let config = JiraBoardConfiguration(boardID: 1, name: "B", columns: [
            JiraBoardColumn(name: "Doing", statusIDs: ["3", "4"])
        ])
        let moves = [transition("a", to: "To Do", statusID: "1"),
                     transition("b", to: "In Review", statusID: "4")]

        // "Doing" is no status's name; the board maps it to ids 3 and 4.
        #expect(JiraQuickCreate.move(into: "Doing", from: moves, using: config)?.id == "b")
        #expect(JiraQuickCreate.move(into: "Doing", from: [moves[0]], using: config) == nil)
    }

    @Test func fallsBackToNameWithoutABoard() {
        let moves = [transition("a", to: "Done", statusID: "9")]
        #expect(JiraQuickCreate.move(into: "Done", from: moves, using: nil)?.id == "a")
    }

    @Test func projectKeyFallsBackToTheSelectedBoardWhenEmpty() {
        let viewModel = JiraViewModel()
        viewModel.selectedBoard = JiraBoard(id: 1, name: "B", type: "kanban", projectKey: "ABC")
        #expect(viewModel.boardProjectKey == "ABC")
    }
}
