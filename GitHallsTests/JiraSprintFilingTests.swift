//
//  JiraSprintFilingTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

/// Jira files every issue created through the API in the backlog. These check
/// that a new issue is moved into the active sprint right after.
private final class SprintAuthoring: JiraIssueAuthoring, @unchecked Sendable {
    var sprints: [JiraSprint]
    var moveFails = false
    private(set) var moves: [(sprint: Int, keys: [String])] = []

    init(sprints: [JiraSprint]) { self.sprints = sprints }

    func projects() async throws -> [JiraProject] { [JiraProject(id: "1", key: "ABC", name: "ABC")] }
    func issueTypes(projectKey: String) async throws -> [JiraIssueType] {
        [JiraIssueType(id: "10", name: "Task", isSubtask: false, hierarchyLevel: 0)]
    }
    func createFields(projectKey: String, issueTypeID: String) async throws -> [JiraCreateField] {
        [JiraCreateField(key: "summary", name: "Summary", required: true)]
    }
    func searchAssignableUsers(query: String, projectKey: String) async throws -> [JiraUser] { [] }
    func priorities() async throws -> [JiraFieldOption] { [] }
    func teams(query: String, autoCompleteURL: String?) async throws -> [JiraFieldOption] { [] }
    func create(_ issue: JiraNewIssue) async throws -> String { "ABC-7" }

    func openSprints(projectKey: String) async throws -> [JiraSprint] { sprints }
    func moveToSprint(_ sprintID: Int, keys: [String]) async throws {
        if moveFails { throw JiraError.http(status: 400, message: "Sprint is closed") }
        moves.append((sprintID, keys))
    }
}

private let future = JiraSprint(id: 6, name: "Sprint 43", state: .future)
private let active = JiraSprint(id: 5, name: "Sprint 42", state: .active)

@MainActor
struct JiraSprintFilingTests {
    private func board() -> JiraViewModel {
        let board = JiraViewModel()
        board.selectedBoard = JiraBoard(id: 1, name: "B", type: "kanban", projectKey: "ABC")
        return board
    }

    @Test func quickCreateFilesTheIssueInTheActiveSprint() async {
        let authoring = SprintAuthoring(sprints: [future, active])
        let model = JiraQuickCreate(authoring: authoring)
        model.summary = "Do it"

        #expect(await model.submit(status: "To Do", board: board()) == .created("ABC-7"))
        #expect(authoring.moves.map(\.sprint) == [5])
        #expect(authoring.moves.first?.keys == ["ABC-7"])
    }

    @Test func quickCreateWithoutAnActiveSprintLeavesTheBacklog() async {
        let authoring = SprintAuthoring(sprints: [future])
        let model = JiraQuickCreate(authoring: authoring)
        model.summary = "Do it"

        #expect(await model.submit(status: "To Do", board: board()) == .created("ABC-7"))
        #expect(authoring.moves.isEmpty)
    }

    @Test func aFailedSprintMoveStillCountsAsCreated() async {
        let authoring = SprintAuthoring(sprints: [active])
        authoring.moveFails = true
        let model = JiraQuickCreate(authoring: authoring)
        let board = board()
        model.summary = "Do it"

        #expect(await model.submit(status: "To Do", board: board) == .created("ABC-7"))
        #expect(board.actionFailed)
        #expect(board.actionMessage?.contains("stayed in the backlog") == true)
    }

    @Test func sheetDefaultsToTheActiveSprintAndMovesThere() async {
        let authoring = SprintAuthoring(sprints: [future, active])
        let model = JiraCreateIssueViewModel(authoring: authoring, projectKey: "ABC")
        await model.load()

        #expect(model.sprints.map(\.id) == [6, 5])
        #expect(model.sprintID == 5)

        model.summary = "Do it"
        #expect(await model.submit() == "ABC-7")
        #expect(authoring.moves.map(\.sprint) == [5])
        #expect(model.warning == nil)
    }

    @Test func sheetCanKeepTheIssueInTheBacklog() async {
        let authoring = SprintAuthoring(sprints: [active])
        let model = JiraCreateIssueViewModel(authoring: authoring, projectKey: "ABC")
        await model.load()
        model.sprintID = nil
        model.summary = "Do it"

        #expect(await model.submit() == "ABC-7")
        #expect(authoring.moves.isEmpty)
    }

    @Test func sheetReportsAFailedMoveWithoutLosingTheIssue() async {
        let authoring = SprintAuthoring(sprints: [active])
        authoring.moveFails = true
        let model = JiraCreateIssueViewModel(authoring: authoring, projectKey: "ABC")
        await model.load()
        model.summary = "Do it"

        #expect(await model.submit() == "ABC-7")
        #expect(model.warning?.contains("ABC-7 was created but stayed in the backlog") == true)
    }

    @Test func parallelSprintsPickTheOneThatStartedFirst() {
        let early = JiraSprint(id: 1, name: "A", state: .active, startDate: Date(timeIntervalSince1970: 100))
        let late = JiraSprint(id: 2, name: "B", state: .active, startDate: Date(timeIntervalSince1970: 200))
        #expect(JiraSprintChoice.defaultSprint(in: [late, future, early])?.id == 1)
        #expect(JiraSprintChoice.defaultSprint(in: [future]) == nil)
    }
}

struct JiraOpenSprintsTests {
    @Test func gathersSprintsFromScrumBoardsOnce() async throws {
        let mock = MockJira { sent in
            switch sent.path {
            case "/rest/agile/1.0/board":
                MockReply(json: #"{"values":[{"id":1,"name":"S","type":"scrum"},{"id":2,"name":"K","type":"kanban"},{"id":3,"name":"S2","type":"scrum"}],"isLast":true}"#)
            case "/rest/agile/1.0/board/1/sprint":
                MockReply(json: #"{"values":[{"id":5,"name":"Sprint 42","state":"active"}],"isLast":true}"#)
            case "/rest/agile/1.0/board/3/sprint":
                MockReply(json: #"{"values":[{"id":6,"name":"Sprint 43","state":"future"},{"id":5,"name":"Sprint 42","state":"active"}],"isLast":true}"#)
            default:
                MockReply(status: 404)
            }
        }

        let sprints = try await mock.client.openSprints(projectKey: "ABC")

        #expect(sprints.map(\.id) == [5, 6])
        #expect(!mock.requests.contains { $0.path == "/rest/agile/1.0/board/2/sprint" })
        #expect(mock.requests[0].query["projectKeyOrId"] == "ABC")
    }
}
