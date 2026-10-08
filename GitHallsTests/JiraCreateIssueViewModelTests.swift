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

@MainActor
struct JiraCreateRequiredFieldsTests {
    /// The shape of the bug report: Description, Team and Original Estimate
    /// are all required by the project's create screen.
    private func requiredStub() -> StubJiraAuthoring {
        var stub = StubJiraAuthoring()
        stub.fields = [
            JiraCreateField(key: "summary", name: "Summary", required: true),
            JiraCreateField(key: "description", name: "Description", required: true, kind: .adf),
            JiraCreateField(key: "customfield_team", name: "Team", required: true, kind: .team),
            JiraCreateField(key: "timetracking", name: "Original Estimate", required: true, kind: .timeTracking)
        ]
        return stub
    }

    private func loaded(_ stub: StubJiraAuthoring) async -> JiraCreateIssueViewModel {
        let model = JiraCreateIssueViewModel(authoring: stub, projectKey: "DEMO")
        await model.load()
        return model
    }

    @Test func requiredDescriptionBlocksSubmit() async {
        let model = await loaded(requiredStub())
        model.summary = "x"
        #expect(model.isRequired("description"))
        #expect(model.problems["description"] == "Required.")
        #expect(!model.canSubmit)
        #expect(model.missing.contains("Description"))
    }

    @Test func teamAndEstimateAreDynamicFields() async {
        let model = await loaded(requiredStub())
        #expect(model.dynamicFields.map(\.key) == ["customfield_team", "timetracking"])
    }

    @Test func estimateMustBeADuration() async {
        let model = await loaded(requiredStub())
        model.extraValues["timetracking"] = "soon"
        #expect(model.problems["timetracking"] == "Use a format like 2h 30m.")
        model.extraValues["timetracking"] = "2h 30m"
        #expect(model.problems["timetracking"] == nil)
    }

    @Test func fullDraftBuildsEveryPayload() async {
        let model = await loaded(requiredStub())
        model.summary = "Title"
        model.descriptionMarkdown = "Body"
        model.extraValues["customfield_team"] = "team-1"
        model.extraValues["timetracking"] = "2h 30m"
        #expect(model.canSubmit)

        let draft = model.draft()
        #expect(draft?.description == "Body")
        #expect(draft?.extra.contains(.custom("customfield_team", .string("team-1")))
                == true)
        #expect(draft?.extra.contains(.custom("timetracking", .object(["originalEstimate": .string("2h 30m")]))) == true)
    }

    @Test func genericKindsBuildTheirPayloads() async {
        var stub = StubJiraAuthoring()
        let options = [JiraFieldOption(id: "1", label: "A"), JiraFieldOption(id: "2", label: "B")]
        stub.fields = [
            JiraCreateField(key: "cf_num", name: "N", required: true, kind: .number),
            JiraCreateField(key: "cf_sel", name: "S", required: true, kind: .option, allowed: options),
            JiraCreateField(key: "cf_multi", name: "M", required: true, kind: .multiOption, allowed: options),
            JiraCreateField(key: "cf_user", name: "U", required: true, kind: .user),
            JiraCreateField(key: "cf_date", name: "D", required: true, kind: .date),
            JiraCreateField(key: "cf_text", name: "T", required: true, kind: .string)
        ]
        let model = await loaded(stub)
        model.summary = "x"
        model.extraValues = ["cf_num": "3.5", "cf_sel": "2", "cf_date": "2026-05-01", "cf_text": "hi"]
        model.extraSelections["cf_multi"] = ["1", "2"]
        model.extraUsers["cf_user"] = [JiraUser(accountID: "acc", displayName: "U")]
        #expect(model.canSubmit)

        let extra = Dictionary(uniqueKeysWithValues: (model.draft()?.extra ?? []).map { ($0.field, $0.value) })
        #expect(extra["cf_num"] == .number(3.5))
        #expect(extra["cf_sel"] == .object(["id": .string("2")]))
        #expect(extra["cf_multi"] == .array([.object(["id": .string("1")]), .object(["id": .string("2")])]))
        #expect(extra["cf_user"] == .object(["accountId": .string("acc")]))
        #expect(extra["cf_date"] == .string("2026-05-01"))
        #expect(extra["cf_text"] == .string("hi"))
    }

    @Test func jiraFieldErrorsLandOnTheirField() async {
        var stub = requiredStub()
        stub.failure = JiraError.fieldErrors(["description": "Description is required.",
                                              "weirdfield": "Odd."])
        let model = await loaded(stub)
        model.summary = "x"
        model.descriptionMarkdown = "d"
        model.extraValues = ["customfield_team": "t", "timetracking": "1h"]

        #expect(await model.submit() == nil)
        #expect(model.fieldErrors["description"] == "Description is required.")
        // A field the sheet has no row for goes to the general message.
        #expect(model.errorMessage == "Odd.")

        model.clearError("description")
        #expect(model.fieldErrors["description"] == nil)
    }

    @Test func inputClassification() {
        func input(_ kind: JiraFieldKind, allowed: [JiraFieldOption] = []) -> JiraFieldInput {
            JiraCreateIssueViewModel.input(for: JiraCreateField(key: "k", name: "k", kind: kind, allowed: allowed))
        }
        #expect(input(.timeTracking) == .duration)
        #expect(input(.team) == .team)
        #expect(input(.userList) == .user)
        #expect(input(.multiOption) == .multiSelect)
        #expect(input(.adf) == .markdown)
        #expect(input(.other("x")) == .text)
        #expect(input(.other("x"), allowed: [JiraFieldOption(id: "1", label: "a")]) == .select)
    }
}

@MainActor
struct JiraCreateReviewFixTests {
    @Test func requiredDateStartsAsTodayAndAllowsSubmit() async {
        var stub = StubJiraAuthoring()
        stub.fields = [JiraCreateField(key: "cf_d", name: "D", required: true, kind: .date)]
        let model = JiraCreateIssueViewModel(authoring: stub, projectKey: "DEMO")
        await model.load()
        model.summary = "x"
        #expect(model.extraValues["cf_d"] == JiraCreateIssueViewModel.dayString(Date()))
        #expect(model.canSubmit)
    }

    @Test func notLoadingOnceEverythingSettled() async {
        let model = JiraCreateIssueViewModel(authoring: StubJiraAuthoring(), projectKey: "DEMO")
        await model.load()
        #expect(!model.isLoading)
    }

    @Test func errorsForRowsTheSheetDoesNotDrawGoToTheGeneralMessage() async {
        var stub = StubJiraAuthoring()
        stub.fields = [JiraCreateField(key: "summary", name: "S", required: true),
                       JiraCreateField(key: "reporter", name: "Reporter")]
        stub.failure = JiraError.fieldErrors(["reporter": "Reporter is not allowed."])
        let model = JiraCreateIssueViewModel(authoring: stub, projectKey: "DEMO")
        await model.load()
        model.summary = "x"

        #expect(await model.submit() == nil)
        #expect(model.fieldErrors["reporter"] == nil)
        #expect(model.errorMessage == "Reporter is not allowed.")
    }
}
