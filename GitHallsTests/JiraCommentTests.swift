//
//  JiraCommentTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraCommentTests {
    private static let commentJSON = """
    {"id":"100","author":{"accountId":"a1","displayName":"Ana"},
     "body":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Looks good"}]}]},
     "created":"2026-08-07T14:02:11.123-0300","updated":"2026-08-07T15:00:00.000-0300"}
    """

    @Test func commentsAreReadOldestFirstAcrossPages() async throws {
        let mock = MockJira { sent in
            sent.query["startAt"] == "0"
                ? MockReply(json: #"{"startAt":0,"total":2,"comments":[\#(Self.commentJSON)]}"#)
                : MockReply(json: #"{"startAt":1,"total":2,"comments":[{"id":"101","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Second"}]}]}}]}"#)
        }

        let comments = try await mock.client.comments(key: "APP-1")

        #expect(comments.map(\.id) == ["100", "101"])
        #expect(comments[0].body == "Looks good")
        #expect(comments[0].author?.displayName == "Ana")
        #expect(comments[0].created != nil && comments[0].updated != nil)
        #expect(comments[1].author == nil)
        #expect(mock.requests[0].path == "/rest/api/3/issue/APP-1/comment")
        #expect(mock.requests[0].query["orderBy"] == "created")
    }

    @Test func addSendsAdfAndReadsTheSavedComment() async throws {
        let mock = MockJira { _ in MockReply(status: 201, json: Self.commentJSON) }

        let saved = try await mock.client.addComment(key: "APP-1", text: "Looks good\n- one\n- two")

        let sent = try #require(mock.requests.first)
        #expect(sent.method == "POST")
        #expect(sent.path == "/rest/api/3/issue/APP-1/comment")
        #expect(JiraADF.plainText(from: sent.json?["body"]) == "Looks good\n• one\n• two")
        #expect(saved.id == "100")
    }

    @Test func editPutsToTheCommentAndDeleteRemovesIt() async throws {
        let mock = MockJira { sent in
            sent.method == "DELETE" ? MockReply(status: 204) : MockReply(json: Self.commentJSON)
        }

        _ = try await mock.client.editComment(key: "APP-1", id: "100", text: "Changed")
        try await mock.client.deleteComment(key: "APP-1", id: "100")

        #expect(mock.requests[0].method == "PUT")
        #expect(mock.requests[0].path == "/rest/api/3/issue/APP-1/comment/100")
        #expect(JiraADF.plainText(from: mock.requests[0].json?["body"]) == "Changed")
        #expect(mock.requests[1].method == "DELETE")
        #expect(mock.requests[1].path == "/rest/api/3/issue/APP-1/comment/100")
    }

    @Test func adfRoundTripsThroughAComment() async throws {
        let text = "Steps:\n1. open\n2. tap\n  • note"
        var echoed: Data?
        let mock = MockJira { sent in
            echoed = sent.body
            let body = (sent.json?["body"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
            return MockReply(json: #"{"id":"7","body":\#(String(data: body, encoding: .utf8) ?? "null")}"#)
        }

        let saved = try await mock.client.addComment(key: "APP-1", text: text)

        #expect(saved.body == text)
        #expect(echoed != nil)
    }

    @Test func malformedAnswerIsAnError() async {
        let mock = MockJira { _ in MockReply(json: "[]") }
        await #expect(throws: JiraError.self) { _ = try await mock.client.addComment(key: "APP-1", text: "x") }
    }
}

@MainActor
struct JiraViewModelCommentTests {
    private func model(_ mock: MockJira, comments: [JiraComment] = []) -> JiraViewModel {
        let viewModel = JiraViewModel()
        let client = mock.client
        viewModel.clientFactory = { client }
        viewModel.commentsByIssue["APP-1"] = comments
        return viewModel
    }

    @Test func loadStoresTheComments() async throws {
        let mock = MockJira { _ in MockReply(json: #"{"total":1,"comments":[{"id":"1","body":null}]}"#) }
        let viewModel = model(mock)

        _ = try await viewModel.loadComments(for: "APP-1")

        #expect(viewModel.commentsByIssue["APP-1"]?.map(\.id) == ["1"])
    }

    @Test func addedCommentIsReplacedByTheSavedOne() async {
        let mock = MockJira { _ in MockReply(status: 201, json: #"{"id":"55","body":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Hi"}]}]}}"#) }
        let viewModel = model(mock)

        #expect(await viewModel.addComment(to: "APP-1", text: "Hi"))

        let comments = viewModel.commentsByIssue["APP-1"] ?? []
        #expect(comments.map(\.id) == ["55"])
        #expect(comments.contains(where: \.isPending) == false)
    }

    @Test func refusedAddRemovesThePendingComment() async {
        let mock = MockJira { _ in MockReply(status: 400, json: #"{"errorMessages":["Too long"]}"#) }
        let viewModel = model(mock)

        #expect(await viewModel.addComment(to: "APP-1", text: "Hi") == false)

        #expect(viewModel.commentsByIssue["APP-1"]?.isEmpty == true)
        #expect(viewModel.actionMessage == "Too long")
    }

    @Test func refusedEditRestoresTheOldText() async {
        let mock = MockJira { _ in MockReply(status: 500) }
        let viewModel = model(mock, comments: [JiraComment(id: "1", body: "old")])

        #expect(await viewModel.editComment(on: "APP-1", id: "1", text: "new") == false)

        #expect(viewModel.commentsByIssue["APP-1"]?.first?.body == "old")
    }

    @Test func refusedDeleteBringsTheCommentBackInPlace() async {
        let mock = MockJira { _ in MockReply(status: 403) }
        let viewModel = model(mock, comments: [JiraComment(id: "1", body: "a"), JiraComment(id: "2", body: "b"), JiraComment(id: "3", body: "c")])

        #expect(await viewModel.deleteComment(on: "APP-1", id: "2") == false)

        #expect(viewModel.commentsByIssue["APP-1"]?.map(\.id) == ["1", "2", "3"])
    }

    @Test func deleteKeepsTheCommentGoneOnSuccess() async {
        let mock = MockJira { _ in MockReply(status: 204) }
        let viewModel = model(mock, comments: [JiraComment(id: "1", body: "a")])

        #expect(await viewModel.deleteComment(on: "APP-1", id: "1"))
        #expect(viewModel.commentsByIssue["APP-1"]?.isEmpty == true)
    }
}
