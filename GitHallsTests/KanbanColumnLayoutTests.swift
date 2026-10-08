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
