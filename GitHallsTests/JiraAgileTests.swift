//
//  JiraAgileTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraAgileTests {
    @Test func boardsReadTypeAndProject() async throws {
        let mock = MockJira { _ in
            MockReply(json: #"{"isLast":true,"values":[{"id":1,"name":"APP board","type":"scrum","location":{"projectKey":"APP"}},{"id":2,"name":"Ops","type":"kanban"}]}"#)
        }

        let boards = try await mock.client.boards(projectKey: "APP")

        #expect(boards.map(\.id) == [1, 2])
        #expect(boards[0].projectKey == "APP" && boards[0].hasSprints)
        #expect(boards[1].hasSprints == false)
        #expect(mock.requests[0].path == "/rest/agile/1.0/board")
        #expect(mock.requests[0].query["projectKeyOrId"] == "APP")
    }

    @Test func configurationMapsColumnsToStatusIDs() async throws {
        let mock = MockJira { _ in
            MockReply(json: """
            {"id":1,"name":"APP board","type":"scrum",
             "columnConfig":{"columns":[
               {"name":"To Do","statuses":[{"id":"10","self":"x"}],"min":null},
               {"name":"Doing","statuses":[{"id":"11"},{"id":"12"}],"max":3},
               {"name":"Done","statuses":[{"id":"13"}]}]},
             "estimation":{"type":"field","field":{"fieldId":"customfield_10016","displayName":"Story Points"}},
             "ranking":{"rankCustomFieldId":10019}}
            """)
        }

        let config = try await mock.client.boardConfiguration(boardID: 1)

        #expect(config.columns.map(\.name) == ["To Do", "Doing", "Done"])
        #expect(config.columns[1].statusIDs == ["11", "12"])
        #expect(config.columns[1].max == 3 && config.columns[0].min == nil)
        #expect(config.estimationFieldID == "customfield_10016")
        #expect(config.rankFieldID == 10019)
        #expect(config.column(forStatusID: "12")?.name == "Doing")
        #expect(config.column(forStatusID: "99") == nil)
        #expect(config.column(forStatusID: nil) == nil)
        #expect(mock.requests[0].path == "/rest/agile/1.0/board/1/configuration")
    }

    @Test func sprintsFilterByStateAndParseDates() async throws {
        let mock = MockJira { _ in
            MockReply(json: """
            {"isLast":true,"values":[
              {"id":5,"name":"Sprint 5","state":"active","startDate":"2026-10-01T10:00:00.000Z","endDate":"2026-10-14T10:00:00.000Z","goal":"Ship","originBoardId":1},
              {"id":6,"name":"Sprint 6","state":"future"}]}
            """)
        }

        let sprints = try await mock.client.sprints(boardID: 1, states: [.active, .future])

        #expect(sprints.map(\.state) == [.active, .future])
        #expect(sprints[0].goal == "Ship" && sprints[0].boardID == 1)
        #expect(sprints[0].startDate != nil && sprints[0].endDate != nil)
        #expect(sprints[1].startDate == nil)
        #expect(mock.requests[0].query["state"] == "active,future")
    }

    @Test func issuePagesTellWhereTheNextOneStarts() async throws {
        let mock = MockJira { _ in
            MockReply(json: """
            {"startAt":0,"maxResults":1,"total":3,"issues":[
              {"key":"APP-1","fields":{"summary":"A","status":{"id":"10","name":"To Do","statusCategory":{"key":"new"}},"customfield_10016":3.0}}]}
            """)
        }

        let page = try await mock.client.boardIssues(boardID: 1, jql: "assignee = currentUser()", startAt: 0, limit: 1,
                                                     storyPointsField: "customfield_10016")

        #expect(page.items.map(\.key) == ["APP-1"])
        #expect(page.items[0].statusID == "10" && page.items[0].storyPoints == 3)
        #expect(page.nextStart == 1 && !page.isLast)
        let sent = mock.requests[0]
        #expect(sent.path == "/rest/agile/1.0/board/1/issue")
        #expect(sent.query["jql"] == "assignee = currentUser()")
        #expect(sent.query["fields"]?.contains("customfield_10016") == true)
    }

    @Test func lastPageHasNoNext() async throws {
        let mock = MockJira { _ in MockReply(json: #"{"startAt":2,"total":3,"issues":[{"key":"APP-3","fields":{"summary":"C"}}]}"#) }

        let page = try await mock.client.backlogIssues(boardID: 1, startAt: 2)

        #expect(page.isLast)
        #expect(mock.requests[0].path == "/rest/agile/1.0/board/1/backlog")
    }

    @Test func sprintIssuesHitTheSprintEndpoint() async throws {
        let mock = MockJira { _ in MockReply(json: #"{"total":0,"issues":[]}"#) }
        let page = try await mock.client.sprintIssues(sprintID: 5)
        #expect(page.items.isEmpty && page.isLast)
        #expect(mock.requests[0].path == "/rest/agile/1.0/sprint/5/issue")
    }

    @Test func moveToSprintAndBacklogPostTheKeys() async throws {
        let mock = MockJira { _ in MockReply(status: 204) }

        try await mock.client.moveToSprint(5, keys: ["APP-1", "APP-2"])
        try await mock.client.moveToBacklog(keys: ["APP-3"])

        #expect(mock.requests[0].method == "POST")
        #expect(mock.requests[0].path == "/rest/agile/1.0/sprint/5/issue")
        #expect(mock.requests[0].json?["issues"] as? [String] == ["APP-1", "APP-2"])
        #expect(mock.requests[1].path == "/rest/agile/1.0/backlog/issue")
        #expect(mock.requests[1].json?["issues"] as? [String] == ["APP-3"])
    }

    @Test func rankSendsBeforeOrAfterAndTheRankField() async throws {
        let mock = MockJira { _ in MockReply(status: 204) }

        try await mock.client.rank(["APP-1"], .before("APP-2"), rankFieldID: 10019)
        try await mock.client.rank(issueKey: "APP-1", before: nil, after: "APP-3")

        #expect(mock.requests[0].method == "PUT")
        #expect(mock.requests[0].path == "/rest/agile/1.0/issue/rank")
        #expect(mock.requests[0].json?["rankBeforeIssue"] as? String == "APP-2")
        #expect(mock.requests[0].json?["rankAfterIssue"] == nil)
        #expect(mock.requests[0].json?["rankCustomFieldId"] as? Int == 10019)
        #expect(mock.requests[1].json?["rankAfterIssue"] as? String == "APP-3")
        #expect(mock.requests[1].json?["rankCustomFieldId"] == nil)
    }

    @Test func rankNeedsAnAnchor() async {
        let mock = MockJira { _ in MockReply(status: 204) }
        await #expect(throws: JiraError.self) { try await mock.client.rank(issueKey: "APP-1", before: nil, after: nil) }
        #expect(mock.requests.isEmpty)
    }

    @Test func rankReportsAnIssueRefusedInsideAMultiStatus() async {
        let mock = MockJira { _ in
            MockReply(status: 207, json: #"{"entries":[{"issueId":1,"status":200},{"issueId":2,"status":400,"errors":["Not on the board"]}]}"#)
        }

        await #expect(throws: JiraError.self) { try await mock.client.rank(["APP-1", "APP-2"], .after("APP-3")) }
    }
}

struct JiraIssueRankingTests {
    private func issue(_ key: String, _ status: String = "To Do") -> JiraIssue {
        JiraIssue(key: key, summary: key, status: status, statusCategory: "new", type: "Task", priority: nil,
                  updated: Date(timeIntervalSince1970: 0))
    }

    private func keys(_ groups: [JiraIssueGroup]?, _ status: String = "To Do") -> [String]? {
        groups?.first { $0.status == status }?.issues.map(\.key)
    }

    private var groups: [JiraIssueGroup] {
        JiraIssueGrouping.byStatus([issue("A"), issue("B"), issue("C"), issue("X", "Doing")])
    }

    @Test func movesBeforeAndAfterWithinAColumn() {
        #expect(keys(JiraIssueRanking.moving("C", to: .before("A"), in: groups)) == ["C", "A", "B"])
        #expect(keys(JiraIssueRanking.moving("A", to: .after("B"), in: groups)) == ["B", "A", "C"])
        #expect(keys(JiraIssueRanking.moving("A", to: .after("C"), in: groups)) == ["B", "C", "A"])
    }

    @Test func otherColumnsAreUntouched() {
        #expect(keys(JiraIssueRanking.moving("C", to: .before("A"), in: groups), "Doing") == ["X"])
    }

    @Test func crossColumnUnknownOrSelfTargetsAreNotShown() {
        #expect(JiraIssueRanking.moving("A", to: .before("X"), in: groups) == nil)
        #expect(JiraIssueRanking.moving("A", to: .before("Z"), in: groups) == nil)
        #expect(JiraIssueRanking.moving("A", to: .before("A"), in: groups) == nil)
    }
}

@MainActor
struct JiraViewModelAgileTests {
    private func issue(_ key: String) -> JiraIssue {
        JiraIssue(key: key, summary: key, status: "To Do", statusCategory: "new", type: "Task", priority: nil,
                  updated: Date(timeIntervalSince1970: 0))
    }

    private func model(_ mock: MockJira) -> JiraViewModel {
        let viewModel = JiraViewModel()
        let client = mock.client
        viewModel.clientFactory = { client }
        viewModel.groups = JiraIssueGrouping.byStatus([issue("A"), issue("B"), issue("C")])
        return viewModel
    }

    private func order(_ viewModel: JiraViewModel) -> [String] {
        viewModel.columns.first?.issues.map(\.key) ?? []
    }

    @Test func rankReordersAtOnceAndKeepsTheOrderOnSuccess() async {
        let mock = MockJira { _ in MockReply(status: 204) }
        let viewModel = model(mock)

        #expect(await viewModel.rank(issue("C"), .before("A")))

        #expect(order(viewModel) == ["C", "A", "B"])
        #expect(mock.requests[0].json?["rankBeforeIssue"] as? String == "A")
    }

    @Test func refusedRankPutsTheColumnBack() async {
        let mock = MockJira { _ in MockReply(status: 400, json: #"{"errorMessages":["Rank failed"]}"#) }
        let viewModel = model(mock)

        #expect(await viewModel.rank(issue("C"), .before("A")) == false)

        #expect(order(viewModel) == ["A", "B", "C"])
        #expect(viewModel.actionMessage == "Rank failed")
        #expect(viewModel.busyIssues.isEmpty)
    }

    @Test func selectingAScrumBoardLoadsConfigurationAndSprints() async {
        let mock = MockJira { sent in
            sent.path.hasSuffix("/configuration")
                ? MockReply(json: #"{"id":1,"columnConfig":{"columns":[{"name":"To Do","statuses":[{"id":"10"}]}]},"ranking":{"rankCustomFieldId":10019}}"#)
                : MockReply(json: #"{"isLast":true,"values":[{"id":5,"name":"S5","state":"active"}]}"#)
        }
        let viewModel = model(mock)

        await viewModel.selectBoard(JiraBoard(id: 1, name: "B", type: "scrum"))

        #expect(viewModel.boardConfiguration?.columns.map(\.name) == ["To Do"])
        #expect(viewModel.sprints.map(\.id) == [5])
    }

    @Test func kanbanBoardsNeverAskForSprints() async {
        let mock = MockJira { _ in MockReply(json: #"{"id":2,"columnConfig":{"columns":[]}}"#) }
        let viewModel = model(mock)

        await viewModel.selectBoard(JiraBoard(id: 2, name: "K", type: "kanban"))

        #expect(mock.requests.map(\.path) == ["/rest/agile/1.0/board/2/configuration"])
        #expect(viewModel.sprints.isEmpty)
    }

    @Test func sprintMovesReportTheirOutcome() async {
        let mock = MockJira { _ in MockReply(status: 204) }
        let viewModel = model(mock)

        #expect(await viewModel.moveToSprint(issue("A"), JiraSprint(id: 5, name: "S5", state: .active)))
        #expect(viewModel.actionMessage == "A moved to S5.")
        let before = viewModel.reloadToken
        #expect(await viewModel.moveToBacklog(issue("A")))
        #expect(viewModel.reloadToken != before)
        #expect(viewModel.actionMessage == "A moved to the backlog.")
    }

    @Test func failedSprintMoveIsReported() async {
        let mock = MockJira { _ in MockReply(status: 400, json: #"{"errorMessages":["Sprint closed"]}"#) }
        let viewModel = model(mock)

        #expect(await viewModel.moveToSprint(issue("A"), JiraSprint(id: 5, name: "S5", state: .closed)) == false)
        #expect(viewModel.actionFailed)
    }
}
