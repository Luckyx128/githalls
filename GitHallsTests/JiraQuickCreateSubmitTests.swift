//
//  JiraQuickCreateSubmitTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

/// Counts what quick-create asks Jira, so "no request" can be asserted.
private final class RecordingAuthoring: JiraIssueAuthoring, @unchecked Sendable {
    var fields: [JiraCreateField]
    private(set) var createFieldsCalls = 0
    private(set) var created: [JiraNewIssue] = []

    init(fields: [JiraCreateField]) { self.fields = fields }

    func projects() async throws -> [JiraProject] { [] }
    func issueTypes(projectKey: String) async throws -> [JiraIssueType] {
        [JiraIssueType(id: "10", name: "Task", isSubtask: false, hierarchyLevel: 0)]
    }
    func createFields(projectKey: String, issueTypeID: String) async throws -> [JiraCreateField] {
        createFieldsCalls += 1
        return fields
    }
    func searchAssignableUsers(query: String, projectKey: String) async throws -> [JiraUser] { [] }
    func priorities() async throws -> [JiraFieldOption] { [] }
    func teams(query: String, autoCompleteURL: String?) async throws -> [JiraFieldOption] { [] }
    func create(_ issue: JiraNewIssue) async throws -> String {
        created.append(issue)
        return "ABC-1"
    }
}

@MainActor
struct JiraQuickCreateSubmitTests {
    private func board() -> JiraViewModel {
        let board = JiraViewModel()
        board.selectedBoard = JiraBoard(id: 1, name: "B", type: "kanban", projectKey: "ABC")
        return board
    }

    private func quick(_ authoring: RecordingAuthoring) -> JiraQuickCreate {
        JiraQuickCreate(authoring: authoring, meta: JiraCreateMetaCache())
    }

    private let summaryOnly = [JiraCreateField(key: "summary", name: "Summary", required: true),
                               JiraCreateField(key: "issuetype", name: "Issue Type", required: true),
                               JiraCreateField(key: "reporter", name: "Reporter", required: true),
                               JiraCreateField(key: "priority", name: "Priority", required: true, hasDefault: true)]

    @Test func createsDirectlyWhenOnlySummaryIsRequired() async {
        let authoring = RecordingAuthoring(fields: summaryOnly)
        let model = quick(authoring)
        model.summary = "  Do it "

        let outcome = await model.submit(status: "In Progress", board: board())

        #expect(outcome == .created("ABC-1"))
        #expect(authoring.created.map(\.summary) == ["Do it"])
        #expect(authoring.created.first?.projectKey == "ABC")
        #expect(model.summary.isEmpty)
    }

    @Test func opensTheSheetWhenSomethingElseIsRequired() async {
        let authoring = RecordingAuthoring(fields: summaryOnly + [
            JiraCreateField(key: "description", name: "Description", required: true, kind: .adf)
        ])
        let model = quick(authoring)
        model.summary = "Do it"

        let outcome = await model.submit(status: "In Progress", board: board())

        #expect(outcome == .needsSheet(CreateIssuePrefill(summary: "Do it", projectKey: "ABC",
                                                          issueTypeID: "10", targetStatus: "In Progress")))
        #expect(authoring.created.isEmpty)
    }

    @Test func aRequiredFieldWithADefaultDoesNotNeedTheSheet() {
        let fields = [JiraCreateField(key: "summary", name: "S", required: true),
                      JiraCreateField(key: "customfield_1", name: "T", required: true, hasDefault: true),
                      JiraCreateField(key: "labels", name: "L", required: false)]
        #expect(JiraQuickCreate.extraRequirements(in: fields).isEmpty)
    }

    @Test func createmetaIsAskedOncePerProjectAndType() async {
        let authoring = RecordingAuthoring(fields: summaryOnly)
        let model = quick(authoring)
        let board = board()

        model.summary = "one"
        _ = await model.submit(status: "To Do", board: board)
        model.summary = "two"
        _ = await model.submit(status: "To Do", board: board)

        #expect(authoring.createFieldsCalls == 1)
        #expect(authoring.created.count == 2)
    }

    @Test func prefillOpensTheSheetOnTheChosenSummaryAndType() async {
        let prefill = CreateIssuePrefill(summary: "Typed", projectKey: "ABC", issueTypeID: "10", targetStatus: "Done")
        var stub = StubJiraAuthoring()
        stub.projects = [JiraProject(id: "1", key: "OTHER", name: "O"), JiraProject(id: "2", key: "ABC", name: "A")]
        stub.types = [JiraIssueType(id: "9", name: "Task", isSubtask: false, hierarchyLevel: 0),
                      JiraIssueType(id: "10", name: "Bug", isSubtask: false, hierarchyLevel: 0)]
        let model = JiraCreateIssueViewModel(authoring: stub, prefill: prefill)
        await model.load()

        #expect(model.summary == "Typed")
        #expect(model.selectedProject?.key == "ABC")
        #expect(model.selectedType?.id == "10")
    }
}
