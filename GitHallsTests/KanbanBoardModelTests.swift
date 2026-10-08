//
//  KanbanBoardModelTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

@MainActor
struct KanbanBoardModelTests {
    private struct FakeRanker: KanbanRanking {
        let result: Bool
        func rank(_ request: KanbanRankRequest) async -> Bool { result }
    }

    private func issue(_ key: String, status: String, id: String) -> JiraIssue {
        var issue = JiraIssue(key: key, summary: key, status: status, statusCategory: "indeterminate",
                              type: "Task", priority: nil, updated: Date(timeIntervalSince1970: 0))
        issue.statusID = id
        return issue
    }

    private func model(ranker: Bool = true, board: Bool = true) throws -> KanbanBoardModel {
        let jira = JiraViewModel()
        jira.groups = JiraIssueGrouping.byStatus([
            issue("A-1", status: "In Dev", id: "2"),
            issue("A-2", status: "In Review", id: "3"),
            issue("A-3", status: "To Do", id: "1")
        ])
        if board {
            jira.boardConfiguration = JiraBoardConfiguration(boardID: 1, name: "B", columns: [
                JiraBoardColumn(name: "Backlog", statusIDs: ["1"]),
                JiraBoardColumn(name: "Doing", statusIDs: ["2", "3"]),
                JiraBoardColumn(name: "Done", statusIDs: ["4"])
            ])
        }
        let suite = try #require(UserDefaults(suiteName: "KanbanBoardModelTests.\(UUID().uuidString)"))
        return KanbanBoardModel(jira: jira, store: KanbanLayoutStore(defaults: suite), ranker: FakeRanker(result: ranker))
    }

    @Test func boardColumnsShowEveryCardOnce() throws {
        let board = try model()
        let keys = board.allColumns.flatMap(\.issues).map(\.key)

        #expect(keys.sorted() == ["A-1", "A-2", "A-3"])
        #expect(board.allColumns.map(\.status) == ["Backlog", "Doing", "Done"])
    }

    @Test func aRankAcrossStatusesInOneColumnSticks() async throws {
        let board = try model()
        let moving = try #require(board.issue(forKey: "A-2"))

        await board.reorder(moving, before: "A-1")

        let doing = try #require(board.allColumns.first { $0.status == "Doing" })
        #expect(doing.issues.map(\.key) == ["A-2", "A-1"])
    }

    @Test func aRefusedRankPutsTheColumnBackAndShakes() async throws {
        let board = try model(ranker: false)
        let moving = try #require(board.issue(forKey: "A-2"))

        await board.reorder(moving, before: "A-1")

        let doing = try #require(board.allColumns.first { $0.status == "Doing" })
        #expect(doing.issues.map(\.key) == ["A-1", "A-2"])
        #expect(board.shakes["A-2"] == 1)
    }

    @Test func aCardWithAMoveInFlightIgnoresAnotherDrop() throws {
        let board = try model()

        #expect(board.drop(cardKey: "A-3", onto: "Done"))
        #expect(!board.drop(cardKey: "A-3", onto: "Doing"))
        #expect(board.allColumns.first { $0.status == "Done" }?.issues.map(\.key) == ["A-3"])
    }
}
