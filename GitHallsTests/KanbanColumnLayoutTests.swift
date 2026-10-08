//
//  KanbanColumnLayoutTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct KanbanColumnLayoutTests {
    private func group(_ status: String) -> JiraIssueGroup {
        JiraIssueGroup(status: status, category: "new", issues: [])
    }

    private var groups: [JiraIssueGroup] { ["To Do", "Doing", "Done"].map(group) }

    @Test func noSavedOrderKeepsTheBoardsOrder() {
        #expect(KanbanColumnLayout().ordered(groups).map(\.status) == ["To Do", "Doing", "Done"])
    }

    @Test func draggingRightLandsAfterTheTarget() {
        var layout = KanbanColumnLayout()
        layout.move("To Do", onto: "Done", within: groups)

        #expect(layout.ordered(groups).map(\.status) == ["Doing", "Done", "To Do"])
    }

    @Test func draggingLeftLandsBeforeTheTarget() {
        var layout = KanbanColumnLayout()
        layout.move("Done", onto: "To Do", within: groups)

        #expect(layout.ordered(groups).map(\.status) == ["Done", "To Do", "Doing"])
    }

    @Test func newColumnsGoAfterTheOnesThePersonPlaced() {
        var layout = KanbanColumnLayout()
        layout.move("Done", onto: "To Do", within: groups)

        let more = groups + [group("Review")]
        #expect(layout.ordered(more).map(\.status) == ["Done", "To Do", "Doing", "Review"])
    }

    @Test func savedColumnsThatVanishedAreIgnored() {
        var layout = KanbanColumnLayout()
        layout.move("Done", onto: "To Do", within: groups)

        let fewer = [group("To Do"), group("Done")]
        #expect(layout.ordered(fewer).map(\.status) == ["Done", "To Do"])
    }

    @Test func shiftStopsAtTheEdges() {
        var layout = KanbanColumnLayout()
        layout.shift("To Do", by: -1, within: groups)
        #expect(layout.order.isEmpty)

        layout.shift("To Do", by: 1, within: groups)
        #expect(layout.ordered(groups).map(\.status) == ["Doing", "To Do", "Done"])
    }

    @Test func togglesFlipAndFlipBack() {
        var layout = KanbanColumnLayout()
        layout.toggleCollapsed("Done")
        layout.toggleHidden("Done")
        #expect(layout.collapsed == ["Done"] && layout.hidden == ["Done"])

        layout.toggleCollapsed("Done")
        layout.toggleHidden("Done")
        #expect(layout.collapsed.isEmpty && layout.hidden.isEmpty)
    }

    @Test func storeKeepsEachQueryApart() throws {
        let suite = try #require(UserDefaults(suiteName: "KanbanColumnLayoutTests.\(UUID().uuidString)"))
        let store = KanbanLayoutStore(defaults: suite)

        var layout = KanbanColumnLayout()
        layout.toggleCollapsed("Done")
        store.save(layout, for: "a")

        #expect(store.load("a") == layout)
        #expect(store.load("b") == KanbanColumnLayout())
    }
}

struct KanbanOrderingTests {
    @Test func movingPutsTheCardJustBeforeTheTarget() {
        #expect(KanbanOrdering.moving("A", before: "C", in: ["A", "B", "C"]) == ["B", "A", "C"])
        #expect(KanbanOrdering.moving("C", before: "A", in: ["A", "B", "C"]) == ["C", "A", "B"])
    }

    @Test func movingOntoItselfOrAStrangerChangesNothing() {
        #expect(KanbanOrdering.moving("A", before: "A", in: ["A", "B"]) == ["A", "B"])
        #expect(KanbanOrdering.moving("A", before: "Z", in: ["A", "B"]) == ["A", "B"])
    }

    @Test func rankingAgainstTheNextCardOrThePreviousAtTheEnd() {
        #expect(KanbanOrdering.request(for: "A", in: ["A", "B"]) == KanbanRankRequest(issueKey: "A", before: "B", after: nil))
        #expect(KanbanOrdering.request(for: "B", in: ["A", "B"]) == KanbanRankRequest(issueKey: "B", before: nil, after: "A"))
        #expect(KanbanOrdering.request(for: "A", in: ["A"]) == nil)
    }
}

struct KanbanShiftTests {
    @Test func shiftStepsOverHiddenColumns() {
        let groups = ["A", "B", "C"].map { JiraIssueGroup(status: $0, category: "new", issues: []) }
        var layout = KanbanColumnLayout()
        layout.toggleHidden("B")

        layout.shift("A", by: 1, within: groups)
        #expect(layout.ordered(groups).map(\.status) == ["B", "C", "A"])
    }
}

struct KanbanBoardColumnsTests {
    private func issue(_ key: String, status: String, id: String?, category: String = "new") -> JiraIssue {
        var issue = JiraIssue(key: key, summary: key, status: status, statusCategory: category,
                              type: "Task", priority: nil, updated: Date(timeIntervalSince1970: 0))
        issue.statusID = id
        return issue
    }

    private let config = JiraBoardConfiguration(boardID: 1, name: "B", columns: [
        JiraBoardColumn(name: "To Do", statusIDs: ["1"]),
        JiraBoardColumn(name: "Doing", statusIDs: ["2", "3"]),
        JiraBoardColumn(name: "Done", statusIDs: ["4"])
    ])

    @Test func withoutABoardColumnsAreStatuses() {
        let groups = KanbanBoardColumns.group([issue("A-1", status: "Review", id: "9")], using: nil)
        #expect(groups.map(\.status) == ["Review"])
    }

    @Test func aBoardColumnHoldsSeveralStatusesAndKeepsEmptyOnes() {
        let groups = KanbanBoardColumns.group([
            issue("A-1", status: "In Dev", id: "2"),
            issue("A-2", status: "In Review", id: "3")
        ], using: config)

        #expect(groups.map(\.status) == ["To Do", "Doing", "Done"])
        #expect(groups[1].issues.map(\.key) == ["A-1", "A-2"])
        #expect(groups[0].issues.isEmpty && groups[2].issues.isEmpty)
    }

    @Test func unmappedIssuesKeepAColumnOfTheirOwn() {
        let groups = KanbanBoardColumns.group([issue("A-1", status: "Parked", id: "99")], using: config)
        #expect(groups.map(\.status) == ["To Do", "Doing", "Done", "Parked"])
    }

    @Test func transitionsMatchByStatusIDOnABoard() {
        let moves = [
            JiraTransition(id: "a", name: "Start", toStatus: "In Dev", toStatusCategory: "indeterminate", toStatusID: "2"),
            JiraTransition(id: "b", name: "Review", toStatus: "In Review", toStatusCategory: "indeterminate", toStatusID: "3"),
            JiraTransition(id: "c", name: "Finish", toStatus: "Closed", toStatusCategory: "done", toStatusID: "4")
        ]

        #expect(KanbanBoardColumns.transitions(moves, into: "Doing", using: config).map(\.id) == ["a", "b"])
        #expect(KanbanBoardColumns.transitions(moves, into: "Closed", using: nil).map(\.id) == ["c"])
    }
}

struct KanbanUnmappedTests {
    @Test func anUnmappedStatusSharingAColumnNameKeepsItsCards() {
        var stray = JiraIssue(key: "A-1", summary: "x", status: "Done", statusCategory: "done",
                              type: "Task", priority: nil, updated: Date(timeIntervalSince1970: 0))
        stray.statusID = "99"
        let config = JiraBoardConfiguration(boardID: 1, name: "B", columns: [JiraBoardColumn(name: "Done", statusIDs: ["4"])])

        let groups = KanbanBoardColumns.group([stray], using: config)
        #expect(groups.map(\.status) == ["Done", "Done (not on board)"])
        #expect(groups[1].issues.count == 1)
    }
}
