//
//  ClockifyClientTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

private extension MockJira {
    /// The same mock transport, answering for Clockify's base path.
    var clockify: ClockifyClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockJiraProtocol.self]
        var client = ClockifyClient(apiKey: "key-123", session: URLSession(configuration: configuration))
        client.baseURL = URL(string: "https://\(host)/api/v1")!
        return client
    }
}

struct ClockifyClientTests {
    private let entryJSON = #"""
    {"id":"e1","description":"[SWEB-1]: Fix","projectId":"p1","taskId":"t1","tagIds":["g1"],
     "timeInterval":{"start":"2026-10-09T13:00:00Z","end":null,"duration":null}}
    """#

    @Test func sendsTheAPIKeyAndReadsTheUser() async throws {
        let mock = MockJira { _ in MockReply(json: #"{"id":"u1","name":"Erik","activeWorkspace":"w1"}"#) }

        let user = try await mock.clockify.user()

        #expect(user == ClockifyUser(id: "u1", name: "Erik", activeWorkspaceID: "w1"))
        #expect(mock.requests[0].path == "/api/v1/user")
        #expect(mock.requests[0].headers["X-Api-Key"] == "key-123")
    }

    @Test func listsActiveProjectsWithTheirClient() async throws {
        let mock = MockJira { _ in
            MockReply(json: #"[{"id":"p1","name":"SIGRA WEB","clientName":"Ambiensys"},{"id":"p2","name":"Infra","clientName":""}]"#)
        }

        let projects = try await mock.clockify.projects(workspaceID: "w1")

        #expect(projects.map(\.label) == ["SIGRA WEB · Ambiensys", "Infra"])
        #expect(mock.requests[0].path == "/api/v1/workspaces/w1/projects")
        #expect(mock.requests[0].query["archived"] == "false")
    }

    @Test func searchesTasksByName() async throws {
        let mock = MockJira { _ in MockReply(json: #"[{"id":"t1","name":"SWEB-6851"}]"#) }

        let tasks = try await mock.clockify.tasks(workspaceID: "w1", projectID: "p1", name: "SWEB-6851")

        #expect(tasks == [ClockifyTask(id: "t1", name: "SWEB-6851")])
        #expect(mock.requests[0].path == "/api/v1/workspaces/w1/projects/p1/tasks")
        #expect(mock.requests[0].query["name"] == "SWEB-6851")
    }

    @Test func manualEntrySendsStartEndProjectTaskAndTags() async throws {
        let mock = MockJira { _ in MockReply(status: 201, json: entryJSON) }
        let start = Date(timeIntervalSince1970: 1_791_550_800)

        _ = try await mock.clockify.addEntry(workspaceID: "w1", ClockifyNewEntry(
            description: "[SWEB-1]: Fix", projectID: "p1", taskID: "t1", tagIDs: ["g1"],
            start: start, end: start.addingTimeInterval(5400)
        ))

        let sent = mock.requests[0]
        #expect(sent.method == "POST")
        #expect(sent.path == "/api/v1/workspaces/w1/time-entries")
        #expect(sent.json?["start"] as? String == ClockifyClient.timestamp(start))
        #expect(sent.json?["end"] as? String == ClockifyClient.timestamp(start.addingTimeInterval(5400)))
        #expect(sent.json?["projectId"] as? String == "p1")
        #expect(sent.json?["taskId"] as? String == "t1")
        #expect(sent.json?["tagIds"] as? [String] == ["g1"])
    }

    @Test func timerLeavesTheEndOut() {
        let body = ClockifyClient.body(for: ClockifyNewEntry(description: "x", start: .now, end: nil))

        #expect(body["end"] == nil)
        #expect(body["projectId"] == nil)
        #expect(body["tagIds"] == nil)
    }

    @Test func readsTheRunningTimer() async throws {
        let mock = MockJira { _ in MockReply(json: "[\(entryJSON)]") }

        let running = try await mock.clockify.runningEntry(workspaceID: "w1", userID: "u1")

        #expect(running?.isRunning == true)
        #expect(running?.taskID == "t1")
        #expect(mock.requests[0].path == "/api/v1/workspaces/w1/user/u1/time-entries")
        #expect(mock.requests[0].query["in-progress"] == "true")
    }

    @Test func stoppingPatchesTheEnd() async throws {
        let stopped = entryJSON.replacingOccurrences(of: #""end":null"#, with: #""end":"2026-10-09T14:00:00.000Z""#)
        let mock = MockJira { _ in MockReply(json: stopped) }

        let entry = try await mock.clockify.stopTimer(workspaceID: "w1", userID: "u1")

        #expect(entry.isRunning == false)
        #expect(mock.requests[0].method == "PATCH")
        #expect(mock.requests[0].json?["end"] is String)
    }

    @Test func mapsErrors() async {
        let rejected = MockJira { _ in MockReply(status: 401) }
        await #expect(throws: ClockifyError.self) { try await rejected.clockify.user() }

        let invalid = MockJira { _ in MockReply(status: 400, json: #"{"message":"Project is archived","code":501}"#) }
        do {
            _ = try await invalid.clockify.addEntry(workspaceID: "w1", ClockifyNewEntry(description: "x", start: .now, end: .now))
            Issue.record("expected an error")
        } catch {
            #expect(error.localizedDescription == "Project is archived")
        }
    }
}

struct ClockifyHelperTests {
    @Test func describesTheIssueLikeTheExtension() {
        #expect(ClockifyViewModel.description(key: "SWEB-6851", summary: "(Front) Melhoria pdf") == "[SWEB-6851]: (Front) Melhoria pdf")
    }

    @Test func picksTheTaskNamedAfterTheKey() {
        let tasks = [ClockifyTask(id: "a", name: "SWEB-68510"), ClockifyTask(id: "b", name: "sweb-6851")]
        #expect(ClockifyViewModel.task(for: "SWEB-6851", in: tasks)?.id == "b")
        #expect(ClockifyViewModel.task(for: "SWEB-685", in: tasks)?.id == "a")
        #expect(ClockifyViewModel.task(for: "APP-1", in: tasks) == nil)
    }

    @Test func projectKeyAndClock() {
        #expect(ClockifyViewModel.jiraProjectKey(of: "SWEB-6851") == "SWEB")
        #expect(ClockifyViewModel.clock(3909) == "01:05:09")
        #expect(ClockifyViewModel.clock(-5) == "00:00:00")
    }

    @Test func manualTimeLandsOnTheChosenDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8))!
        let time = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 10, minute: 37))!

        let combined = IssueClockifyView.combine(day: day, time: time, calendar: calendar)

        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: combined)
        #expect(parts == DateComponents(year: 2026, month: 10, day: 9, hour: 10, minute: 37))
    }
}
