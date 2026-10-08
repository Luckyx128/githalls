//
//  JiraTransportTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}

private final class Waits: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [TimeInterval] = []
    func add(_ seconds: TimeInterval) { lock.lock(); all.append(seconds); lock.unlock() }
    var values: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return all }
}

struct JiraTransportTests {
    private let issue = #"{"key":"APP-1","fields":{"summary":"S"}}"#

    @Test func searchPageHandsBackTheCursor() async throws {
        let mock = MockJira { _ in MockReply(json: #"{"issues":[\#(issue)],"nextPageToken":"tok2"}"#) }

        let page = try await mock.client.searchPage(jql: "project = APP", limit: 1, pageToken: "tok1")

        #expect(page.items.map(\.key) == ["APP-1"])
        #expect(page.nextPageToken == "tok2" && !page.isLast)
        let body = mock.requests[0].json
        #expect(body?["nextPageToken"] as? String == "tok1")
        #expect(body?["maxResults"] as? Int == 1)
        #expect(mock.requests[0].path == "/rest/api/3/search/jql")
    }

    @Test func searchFollowsTokensUntilTheLimit() async throws {
        let counter = Counter()
        let mock = MockJira { _ in
            let page = counter.next()
            return MockReply(json: #"{"issues":[{"key":"APP-\#(page)","fields":{"summary":"S"}}],"nextPageToken":"t\#(page)"}"#)
        }

        let issues = try await mock.client.search(jql: "x", limit: 3)

        #expect(issues.map(\.key) == ["APP-1", "APP-2", "APP-3"])
        #expect(mock.requests.count == 3)
        #expect(mock.requests[1].json?["nextPageToken"] as? String == "t1")
        #expect(mock.requests[2].json?["maxResults"] as? Int == 1)
    }

    @Test func searchStopsWhenTheLastPageSaysSo() async throws {
        let mock = MockJira { _ in MockReply(json: #"{"issues":[\#(issue)],"isLast":true,"nextPageToken":"ignored"}"#) }

        let issues = try await mock.client.search(jql: "x", limit: 50)

        #expect(issues.count == 1)
        #expect(mock.requests.count == 1)
    }

    @Test func searchCapsRequestsPerPageAtJirasLimit() async throws {
        let mock = MockJira { _ in MockReply(json: #"{"issues":[],"isLast":true}"#) }
        _ = try await mock.client.search(jql: "x", limit: 500)
        #expect(mock.requests[0].json?["maxResults"] as? Int == 100)
    }

    @Test func aRateLimitIsWaitedOutAndRetried() async throws {
        let counter = Counter()
        let waits = Waits()
        let mock = MockJira { _ in
            counter.next() == 1
                ? MockReply(status: 429, headers: ["Retry-After": "7"])
                : MockReply(json: #"{"accountId":"a1","displayName":"Ana"}"#)
        }
        var client = mock.client
        client.retrySleep = { waits.add($0) }

        let me = try await client.myself()

        #expect(me.accountID == "a1")
        #expect(waits.values == [7])
        #expect(mock.requests.count == 2)
    }

    @Test func aWriteIsRetriedWithItsBodyIntact() async throws {
        let counter = Counter()
        let mock = MockJira { _ in
            counter.next() == 1 ? MockReply(status: 429, headers: ["Retry-After": "1"]) : MockReply(status: 204)
        }

        try await mock.client.edit(key: "APP-1", [.summary("Again")])

        #expect(mock.requests.count == 2)
        #expect(mock.requests.map { $0.fields?["summary"] as? String } == ["Again", "Again"])
    }

    @Test func persistentRateLimitSurfacesAfterTheRetries() async {
        let waits = Waits()
        let mock = MockJira { _ in MockReply(status: 429, headers: ["Retry-After": "2"]) }
        var client = mock.client
        client.retrySleep = { waits.add($0) }

        do {
            _ = try await client.myself()
            Issue.record("expected a rate limit error")
        } catch JiraError.rateLimited(let retryAfter) {
            #expect(retryAfter == 2)
        } catch {
            Issue.record("unexpected error \(error)")
        }

        #expect(mock.requests.count == 3)
        #expect(waits.values == [2, 2])
    }

    @Test func aLongRetryAfterIsReportedNotSlept() async {
        let waits = Waits()
        let mock = MockJira { _ in MockReply(status: 429, headers: ["Retry-After": "300"]) }
        var client = mock.client
        client.retrySleep = { waits.add($0) }

        await #expect(throws: JiraError.self) { _ = try await client.myself() }

        #expect(mock.requests.count == 1)
        #expect(waits.values.isEmpty)
    }

    @Test func aMissingRetryAfterIsTreatedAsALongWait() async {
        let mock = MockJira { _ in MockReply(status: 429) }
        do {
            _ = try await mock.client.myself()
            Issue.record("expected a rate limit error")
        } catch JiraError.rateLimited(let retryAfter) {
            #expect(retryAfter == 60)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(mock.requests.count == 1)
    }

    @Test func otherFailuresAreNotRetried() async {
        let mock = MockJira { _ in MockReply(status: 500, json: #"{"errorMessages":["Boom"]}"#) }
        await #expect(throws: JiraError.self) { _ = try await mock.client.myself() }
        #expect(mock.requests.count == 1)
    }

    @Test func pagedListsStopAtTheCapIfJiraNeverSaysLast() async throws {
        let mock = MockJira { _ in MockReply(json: #"{"isLast":false,"values":[{"id":"1","key":"APP","name":"App"}]}"#) }

        let projects = try await mock.client.projects()

        #expect(mock.requests.count == JiraClient.maxPages)
        #expect(projects.count == JiraClient.maxPages)
    }

    @Test func aMalformedPageIsAnError() async {
        let mock = MockJira { _ in MockReply(json: #"{"nope":true}"#) }
        await #expect(throws: JiraError.self) { _ = try await mock.client.projects() }
    }
}
