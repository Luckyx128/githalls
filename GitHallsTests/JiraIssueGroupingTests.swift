//
//  JiraIssueGroupingTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraIssueGroupingTests {
    private func issue(_ key: String, _ status: String, _ category: String, summary: String? = nil) -> JiraIssue {
        JiraIssue(
            key: key,
            summary: summary ?? key,
            status: status,
            statusCategory: category,
            type: "Task",
            priority: nil,
            updated: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func columnsRunInWorkflowOrder() {
        // Rank order interleaves statuses; the board still reads left to right.
        let groups = JiraIssueGrouping.byStatus([
            issue("A-1", "In Progress", "indeterminate"),
            issue("A-2", "To Do", "new"),
            issue("A-3", "In Progress", "indeterminate")
        ])

        #expect(groups.map(\.status) == ["To Do", "In Progress"])
        #expect(groups[1].count == 2)
    }

    @Test func withinACategoryTheOrderJiraReturnedIsKept() {
        let groups = JiraIssueGrouping.byStatus([
            issue("A-1", "In Review", "indeterminate"),
            issue("A-2", "In Progress", "indeterminate"),
            issue("A-3", "Selected", "new"),
            issue("A-4", "To Do", "new")
        ])

        #expect(groups.map(\.status) == ["Selected", "To Do", "In Review", "In Progress"])
    }

    @Test func finishedWorkSinksToTheBottom() {
        let groups = JiraIssueGrouping.byStatus([
            issue("A-1", "Done", "done"),
            issue("A-2", "To Do", "new"),
            issue("A-3", "Released", "done"),
            issue("A-4", "In Review", "indeterminate")
        ])

        #expect(groups.map(\.status) == ["To Do", "In Review", "Done", "Released"])
        #expect(groups.last?.isDone == true)
    }

    @Test func filterKeepsEveryColumnAndOnlyTheMatchingCards() {
        let groups = JiraIssueGrouping.byStatus([
            issue("APP-1", "To Do", "new", summary: "Login screen"),
            issue("APP-2", "To Do", "new", summary: "Kanban board"),
            issue("APP-3", "Done", "done", summary: "Crash on login")
        ])

        let filtered = JiraIssueGrouping.filter(groups, by: "login")

        #expect(filtered.count == 2)
        #expect(filtered[0].issues.map(\.key) == ["APP-1"])
        #expect(filtered[1].issues.map(\.key) == ["APP-3"])

        // The key matches too, case aside.
        #expect(JiraIssueGrouping.filter(groups, by: "app-2")[0].issues.map(\.key) == ["APP-2"])

        // Blank means no filter.
        #expect(JiraIssueGrouping.filter(groups, by: "  ").map(\.count) == groups.map(\.count))
    }

    @Test func noIssuesMeansNoColumns() {
        #expect(JiraIssueGrouping.byStatus([]).isEmpty)
    }
}
