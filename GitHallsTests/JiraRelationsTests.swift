//
//  JiraRelationsTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraRelationsTests {
    @Test func linkTypesReadBothPhrases() async throws {
        let mock = MockJira { _ in
            MockReply(json: #"{"issueLinkTypes":[{"id":"1","name":"Blocks","inward":"is blocked by","outward":"blocks"}]}"#)
        }

        let types = try await mock.client.linkTypes()

        #expect(types == [JiraLinkType(id: "1", name: "Blocks", inward: "is blocked by", outward: "blocks")])
        #expect(mock.requests[0].path == "/rest/api/3/issueLinkType")
    }

    @Test func linkPostsTypeAndBothEnds() async throws {
        let mock = MockJira { _ in MockReply(status: 201) }

        try await mock.client.link("Blocks", inward: "APP-2", outward: "APP-1")
        try await mock.client.deleteLink(id: "900")

        let body = mock.requests[0].json
        #expect(mock.requests[0].path == "/rest/api/3/issueLink")
        #expect((body?["type"] as? [String: String]) == ["name": "Blocks"])
        #expect((body?["inwardIssue"] as? [String: String]) == ["key": "APP-2"])
        #expect((body?["outwardIssue"] as? [String: String]) == ["key": "APP-1"])
        #expect(mock.requests[1].method == "DELETE")
        #expect(mock.requests[1].path == "/rest/api/3/issueLink/900")
    }

    @Test func issueDecodingReadsLinksAndSubtasks() throws {
        let raw = try JSONSerialization.jsonObject(with: Data("""
        {"key":"APP-2","fields":{"summary":"S",
         "issuelinks":[
           {"id":"1","type":{"name":"Blocks","inward":"is blocked by","outward":"blocks"},
            "inwardIssue":{"key":"APP-1","fields":{"summary":"Blocker","status":{"name":"Doing","statusCategory":{"key":"indeterminate"}},"issuetype":{"name":"Bug"}}}},
           {"id":"2","type":{"name":"Relates","inward":"relates to","outward":"relates to"},
            "outwardIssue":{"key":"APP-5","fields":{"summary":"Other"}}}],
         "subtasks":[{"key":"APP-3","fields":{"summary":"Child","status":{"name":"To Do","statusCategory":{"key":"new"}}}}]}}
        """.utf8)) as! [String: Any]

        let issue = try #require(JiraClient.issue(from: raw))

        #expect(issue.links?.map(\.label) == ["is blocked by", "relates to"])
        #expect(issue.links?.map(\.direction) == [.inward, .outward])
        #expect(issue.links?[0].issue.summary == "Blocker" && issue.links?[0].issue.type == "Bug")
        #expect(issue.subtasks?.map(\.key) == ["APP-3"])
        #expect(issue.subtasks?[0].statusCategory == "new")
    }

    @Test func issueWithLinksSurvivesCodable() throws {
        var issue = JiraIssue(key: "A-1", summary: "s", status: "x", statusCategory: "new", type: "t", priority: nil, updated: Date())
        issue.links = [JiraIssueLink(id: "1", typeName: "Blocks", label: "blocks", direction: .outward, issue: JiraIssueRef(key: "A-2", summary: "b"))]
        let decoded = try JSONDecoder().decode(JiraIssue.self, from: JSONEncoder().encode(issue))
        #expect(decoded == issue)
    }

    @Test func setParentUsesTheParentField() async throws {
        let mock = MockJira { _ in MockReply(status: 204) }

        try await mock.client.setParent(key: "APP-3", parentKey: "APP-1")
        try await mock.client.setParent(key: "APP-3", parentKey: nil)

        #expect((mock.requests[0].fields?["parent"] as? [String: String]) == ["key": "APP-1"])
        #expect(mock.requests[1].fields?["parent"] is NSNull)
    }

    @Test func subtaskIsCreatedWithItsParent() async throws {
        let mock = MockJira { _ in MockReply(status: 201, json: #"{"key":"APP-4"}"#) }
        var draft = JiraNewIssue(projectKey: "APP", issueTypeID: "11", summary: "Child")
        draft.parentKey = "APP-1"

        _ = try await mock.client.create(draft)

        #expect((mock.requests[0].fields?["parent"] as? [String: String]) == ["key": "APP-1"])
    }

    @Test func watchersListAddAndRemove() async throws {
        let mock = MockJira { sent in
            sent.method == "GET"
                ? MockReply(json: #"{"watchCount":1,"watchers":[{"accountId":"a1","displayName":"Ana"}]}"#)
                : MockReply(status: 204)
        }

        let watchers = try await mock.client.watchers(key: "APP-1")
        try await mock.client.addWatcher(key: "APP-1", accountID: "a2")
        try await mock.client.removeWatcher(key: "APP-1", accountID: "a2")

        #expect(watchers.map(\.displayName) == ["Ana"])
        // A bare JSON string, quotes included.
        #expect(String(data: mock.requests[1].body ?? Data(), encoding: .utf8) == "\"a2\"")
        #expect(mock.requests[1].method == "POST")
        #expect(mock.requests[2].method == "DELETE")
        #expect(mock.requests[2].query["accountId"] == "a2")
        #expect(mock.requests[2].path == "/rest/api/3/issue/APP-1/watchers")
    }

    @Test func votesReadCountAndOwnVote() async throws {
        let mock = MockJira { sent in
            sent.method == "GET" ? MockReply(json: #"{"votes":3,"hasVoted":true}"#) : MockReply(status: 204)
        }

        let votes = try await mock.client.votes(key: "APP-1")
        try await mock.client.vote(key: "APP-1")
        try await mock.client.unvote(key: "APP-1")

        #expect(votes == JiraVotes(count: 3, hasVoted: true))
        #expect(mock.requests.map(\.method) == ["GET", "POST", "DELETE"])
        #expect(mock.requests.allSatisfy { $0.path == "/rest/api/3/issue/APP-1/votes" })
    }
}

struct JiraFilesTests {
    @Test func worklogsAreReadWithDurationAndComment() async throws {
        let mock = MockJira { _ in
            MockReply(json: """
            {"total":1,"worklogs":[{"id":"7","author":{"accountId":"a1","displayName":"Ana"},"timeSpentSeconds":5400,
              "started":"2026-08-07T14:02:11.123-0300",
              "comment":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Pairing"}]}]}}]}
            """)
        }

        let logs = try await mock.client.worklogs(key: "APP-1")

        #expect(logs.count == 1)
        #expect(logs[0].timeSpent == "1h 30m" && logs[0].comment == "Pairing" && logs[0].started != nil)
    }

    @Test func addWorklogSendsSecondsStartAndAdfComment() async throws {
        let mock = MockJira { _ in MockReply(status: 201, json: #"{"id":"8","timeSpentSeconds":3600}"#) }
        let started = Date(timeIntervalSince1970: 1_800_000_000)

        let log = try await mock.client.addWorklog(key: "APP-1", seconds: 3600, started: started, comment: "Review")

        let body = try #require(mock.requests[0].json)
        #expect(body["timeSpentSeconds"] as? Int == 3600)
        #expect((body["started"] as? String).flatMap(JiraClient.timestamp.date(from:)) == started)
        #expect(JiraADF.plainText(from: body["comment"]) == "Review")
        #expect(mock.requests[0].path == "/rest/api/3/issue/APP-1/worklog")
        #expect(log.id == "8")
    }

    @Test func addWorklogOmitsAnEmptyComment() async throws {
        let mock = MockJira { _ in MockReply(status: 201, json: #"{"id":"8","timeSpentSeconds":60}"#) }
        _ = try await mock.client.addWorklog(key: "APP-1", seconds: 60, comment: "  ")
        #expect(mock.requests[0].json?["comment"] == nil && mock.requests[0].json?["started"] == nil)
    }

    @Test func deleteWorklogHitsTheWorklogPath() async throws {
        let mock = MockJira { _ in MockReply(status: 204) }
        try await mock.client.deleteWorklog(key: "APP-1", id: "8")
        #expect(mock.requests[0].method == "DELETE" && mock.requests[0].path == "/rest/api/3/issue/APP-1/worklog/8")
    }

    @Test func durationsReadTheWayJiraWritesThem() {
        #expect(JiraWorklog.format(seconds: 0) == "0m")
        #expect(JiraWorklog.format(seconds: 60) == "1m")
        #expect(JiraWorklog.format(seconds: 28_800) == "1d")
        #expect(JiraWorklog.format(seconds: 28_800 + 3600 + 900) == "1d 1h 15m")
    }

    private static let attachmentJSON = { (host: String) in
        #"{"id":"20","filename":"a.png","size":12,"mimeType":"image/png","content":"https://\#(host)/rest/api/3/attachment/content/20","thumbnail":"https://\#(host)/thumb/20","author":{"accountId":"a1","displayName":"Ana"},"created":"2026-08-07T14:02:11.123-0300"}"#
    }

    @Test func attachmentsComeFromTheIssueFields() async throws {
        let box = Box()
        let mock = MockJira { _ in MockReply(json: #"{"fields":{"attachment":[\#(Self.attachmentJSON(box.host))]}}"#) }
        box.host = mock.host

        let list = try await mock.client.attachments(key: "APP-1")

        #expect(list.map(\.filename) == ["a.png"])
        #expect(list[0].isImage && list[0].size == 12 && list[0].thumbnailURL != nil)
        #expect(mock.requests[0].query["fields"] == "attachment")
    }

    @Test func uploadIsMultipartWithTheNoCheckHeader() async throws {
        let box = Box()
        let mock = MockJira { _ in MockReply(json: "[\(Self.attachmentJSON(box.host))]") }
        box.host = mock.host

        let stored = try await mock.client.uploadAttachment(key: "APP-1", filename: "a\"b.png", data: Data("PNGDATA".utf8), mimeType: "image/png")

        let sent = mock.requests[0]
        #expect(sent.method == "POST" && sent.path == "/rest/api/3/issue/APP-1/attachments")
        #expect(sent.headers["X-Atlassian-Token"] == "no-check")
        #expect(sent.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(data: sent.body ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("name=\"file\"; filename=\"a_b.png\""))
        #expect(body.contains("PNGDATA"))
        #expect(stored.count == 1)
    }

    @Test func downloadSendsCredentialsToTheSiteOnly() async throws {
        let mock = MockJira { _ in MockReply(data: Data("BYTES".utf8)) }
        let own = JiraAttachment(id: "1", filename: "a", contentURL: URL(string: "https://\(mock.host)/secure/attachment/1/a")!)
        let foreign = JiraAttachment(id: "2", filename: "b", contentURL: URL(string: "https://evil.example/b")!)

        let data = try await mock.client.downloadAttachment(own)

        #expect(data == Data("BYTES".utf8))
        #expect(mock.requests[0].headers["Authorization"]?.hasPrefix("Basic ") == true)
        await #expect(throws: JiraError.self) { _ = try await mock.client.downloadAttachment(foreign) }
        #expect(mock.requests.count == 1)
    }

    @Test func deleteAttachmentHitsTheAttachmentPath() async throws {
        let mock = MockJira { _ in MockReply(status: 204) }
        try await mock.client.deleteAttachment(id: "20")
        #expect(mock.requests[0].method == "DELETE" && mock.requests[0].path == "/rest/api/3/attachment/20")
    }
}

private final class Box: @unchecked Sendable { var host = "" }

@MainActor
struct JiraViewModelRelationsTests {
    private func issue(links: [JiraIssueLink]? = []) -> JiraIssue {
        var issue = JiraIssue(key: "APP-1", summary: "s", status: "To Do", statusCategory: "new", type: "Task",
                              priority: nil, updated: Date(timeIntervalSince1970: 0))
        issue.links = links
        return issue
    }

    private func model(_ mock: MockJira, board: [JiraIssue] = []) -> JiraViewModel {
        let viewModel = JiraViewModel()
        let client = mock.client
        viewModel.clientFactory = { client }
        viewModel.groups = JiraIssueGrouping.byStatus(board)
        return viewModel
    }

    private let blocks = JiraLinkType(id: "1", name: "Blocks", inward: "is blocked by", outward: "blocks")

    @Test func linkingMapsDirectionToInwardAndOutwardEnds() async {
        let mock = MockJira { _ in MockReply(status: 201) }
        let viewModel = model(mock, board: [issue()])

        #expect(await viewModel.link(issue(), blocks, direction: .outward, to: "APP-2"))

        let body = mock.requests[0].json
        #expect((body?["outwardIssue"] as? [String: String]) == ["key": "APP-1"])
        #expect((body?["inwardIssue"] as? [String: String]) == ["key": "APP-2"])
        #expect(viewModel.boardIssue(for: "APP-1")?.links?.count == 1)
    }

    @Test func refusedLinkLeavesTheCardAsItWas() async {
        let mock = MockJira { _ in MockReply(status: 404, json: #"{"errorMessages":["No such issue"]}"#) }
        let viewModel = model(mock, board: [issue()])

        #expect(await viewModel.link(issue(), blocks, direction: .inward, to: "NOPE-1") == false)

        #expect(viewModel.boardIssue(for: "APP-1")?.links == [])
        #expect(viewModel.actionMessage == "No such issue")
    }

    @Test func unlinkRollsBackWhenRefused() async {
        let link = JiraIssueLink(id: "9", typeName: "Blocks", label: "blocks", direction: .outward, issue: JiraIssueRef(key: "APP-2", summary: "x"))
        let mock = MockJira { _ in MockReply(status: 500) }
        let viewModel = model(mock, board: [issue(links: [link])])

        #expect(await viewModel.unlink(issue(links: [link]), link) == false)
        #expect(viewModel.boardIssue(for: "APP-1")?.links == [link])
    }

    @Test func parentIsShownAtOnceAndRolledBack() async {
        let ok = MockJira { _ in MockReply(status: 204) }
        let viewModel = model(ok, board: [issue()])
        #expect(await viewModel.setParent(issue(), JiraIssueRef(key: "APP-9", summary: "Epic")))
        #expect(viewModel.boardIssue(for: "APP-1")?.parentKey == "APP-9")

        let refused = MockJira { _ in MockReply(status: 400) }
        let other = model(refused, board: [issue()])
        #expect(await other.setParent(issue(), JiraIssueRef(key: "APP-9", summary: "Epic")) == false)
        #expect(other.boardIssue(for: "APP-1")?.parentKey == nil)
    }

    @Test func voteMovesTheCountFirstAndRollsBack() async {
        let ok = MockJira { _ in MockReply(status: 204) }
        let viewModel = model(ok)
        viewModel.votesByIssue["APP-1"] = JiraVotes(count: 2, hasVoted: false)
        #expect(await viewModel.setVote(true, on: "APP-1"))
        #expect(viewModel.votesByIssue["APP-1"] == JiraVotes(count: 3, hasVoted: true))

        let refused = MockJira { _ in MockReply(status: 403) }
        let other = model(refused)
        other.votesByIssue["APP-1"] = JiraVotes(count: 2, hasVoted: false)
        #expect(await other.setVote(true, on: "APP-1") == false)
        #expect(other.votesByIssue["APP-1"] == JiraVotes(count: 2, hasVoted: false))
    }

    @Test func watchingAddsTheUserAndRollsBack() async {
        let ana = JiraUser(accountID: "a1", displayName: "Ana")
        let ok = MockJira { _ in MockReply(status: 204) }
        let viewModel = model(ok)
        #expect(await viewModel.setWatcher(ana, watching: true, on: "APP-1"))
        #expect(viewModel.watchersByIssue["APP-1"] == [ana])
        #expect(await viewModel.setWatcher(ana, watching: false, on: "APP-1"))
        #expect(viewModel.watchersByIssue["APP-1"] == [])

        let refused = MockJira { _ in MockReply(status: 403) }
        let other = model(refused)
        other.watchersByIssue["APP-1"] = [ana]
        #expect(await other.setWatcher(ana, watching: false, on: "APP-1") == false)
        #expect(other.watchersByIssue["APP-1"] == [ana])
    }

    @Test func loggedWorkReplacesItsPendingEntry() async {
        let mock = MockJira { _ in MockReply(status: 201, json: #"{"id":"8","timeSpentSeconds":3600}"#) }
        let viewModel = model(mock)

        #expect(await viewModel.logWork(on: "APP-1", seconds: 3600))

        #expect(viewModel.worklogsByIssue["APP-1"]?.map(\.id) == ["8"])
        #expect(viewModel.actionMessage == "Logged 1h on APP-1.")
    }

    @Test func refusedWorklogsVanishOrReturn() async {
        let refused = MockJira { _ in MockReply(status: 400, json: #"{"errorMessages":["Bad"]}"#) }
        let viewModel = model(refused)
        #expect(await viewModel.logWork(on: "APP-1", seconds: 60) == false)
        #expect(viewModel.worklogsByIssue["APP-1"]?.isEmpty == true)

        viewModel.worklogsByIssue["APP-1"] = [JiraWorklog(id: "1", timeSpentSeconds: 60)]
        #expect(await viewModel.deleteWorklog(on: "APP-1", id: "1") == false)
        #expect(viewModel.worklogsByIssue["APP-1"]?.map(\.id) == ["1"])
    }

    @Test func attachmentDeleteRollsBack() async {
        let file = JiraAttachment(id: "20", filename: "a.png", contentURL: URL(string: "https://x.test/a")!)
        let refused = MockJira { _ in MockReply(status: 403) }
        let viewModel = model(refused)
        viewModel.attachmentsByIssue["APP-1"] = [file]

        #expect(await viewModel.deleteAttachment(on: "APP-1", id: "20") == false)
        #expect(viewModel.attachmentsByIssue["APP-1"] == [file])
    }

    @Test func uploadAppendsWhatJiraStored() async {
        let box = Box()
        let mock = MockJira { _ in
            MockReply(json: #"[{"id":"21","filename":"b.txt","content":"https://\#(box.host)/c/21"}]"#)
        }
        box.host = mock.host
        let viewModel = model(mock)

        #expect(await viewModel.attach(to: "APP-1", filename: "b.txt", data: Data("x".utf8), mimeType: "text/plain"))
        #expect(viewModel.attachmentsByIssue["APP-1"]?.map(\.filename) == ["b.txt"])
    }
}
