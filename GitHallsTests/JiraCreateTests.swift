//
//  JiraCreateTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraCreateTests {
    @Test func projectsReadEveryPage() async throws {
        let mock = MockJira { sent in
            sent.query["startAt"] == "0"
                ? MockReply(json: #"{"isLast":false,"values":[{"id":"1","key":"APP","name":"App"}]}"#)
                : MockReply(json: #"{"isLast":true,"values":[{"id":"2","key":"OPS","name":"Ops"}]}"#)
        }

        let projects = try await mock.client.projects()

        #expect(projects.map(\.key) == ["APP", "OPS"])
        #expect(mock.requests.count == 2)
        #expect(mock.requests[0].path == "/rest/api/3/project/search")
        #expect(mock.requests[1].query["startAt"] == "1")
    }

    @Test func issueTypesFlagSubtasks() async throws {
        let mock = MockJira { _ in
            MockReply(json: #"{"total":2,"issueTypes":[{"id":"10","name":"Task","subtask":false,"hierarchyLevel":0},{"id":"11","name":"Sub-task","subtask":true,"hierarchyLevel":-1}]}"#)
        }

        let types = try await mock.client.issueTypes(projectKey: "APP")

        #expect(types.map(\.name) == ["Task", "Sub-task"])
        #expect(types[1].isSubtask && types[1].hierarchyLevel == -1)
        #expect(mock.requests[0].path == "/rest/api/3/issue/createmeta/APP/issuetypes")
    }

    @Test func createFieldsCarryRequirednessKindAndOptions() async throws {
        let mock = MockJira { _ in
            MockReply(json: """
            {"total":4,"fields":[
              {"fieldId":"summary","name":"Summary","required":true,"schema":{"type":"string","system":"summary"}},
              {"fieldId":"description","name":"Description","required":false,"schema":{"type":"string","system":"description"}},
              {"fieldId":"priority","name":"Priority","required":false,"hasDefaultValue":true,"schema":{"type":"priority"},
               "allowedValues":[{"id":"1","name":"High"},{"id":"3","name":"Low"}]},
              {"fieldId":"customfield_10050","name":"Team","required":true,"schema":{"type":"option"},"allowedValues":[{"id":"7","value":"Blue"}]}
            ]}
            """)
        }

        let fields = try await mock.client.createFields(projectKey: "APP", issueTypeID: "10")

        #expect(fields.map(\.key) == ["summary", "description", "priority", "customfield_10050"])
        #expect(fields.filter(\.required).map(\.key) == ["summary", "customfield_10050"])
        #expect(fields[1].kind == .adf)
        #expect(fields[2].kind == .priority && fields[2].hasDefault)
        #expect(fields[2].allowed.map(\.label) == ["High", "Low"])
        #expect(fields[3].allowed == [JiraFieldOption(id: "7", label: "Blue")])
        #expect(mock.requests[0].path == "/rest/api/3/issue/createmeta/APP/issuetypes/10")
    }

    @Test func createWritesTheFieldsAndAnswersTheKey() async throws {
        let mock = MockJira { _ in MockReply(status: 201, json: #"{"id":"1001","key":"APP-42"}"#) }

        var issue = JiraNewIssue(projectKey: "APP", issueTypeID: "10", summary: "Crash on launch")
        issue.description = "Steps:\n- open\n- crash"
        issue.priorityID = "2"
        issue.labels = ["ios"]
        issue.componentIDs = ["5"]
        issue.assigneeAccountID = "acc-1"
        issue.parentKey = "APP-1"
        issue.dueDate = "2026-12-01"
        issue.extra = [.storyPoints(fieldID: "customfield_10016", 3)]

        let key = try await mock.client.create(issue)

        #expect(key == "APP-42")
        let sent = try #require(mock.requests.first)
        #expect(sent.method == "POST")
        #expect(sent.path == "/rest/api/3/issue")
        let fields = try #require(sent.fields)
        #expect((fields["project"] as? [String: String]) == ["key": "APP"])
        #expect((fields["issuetype"] as? [String: String]) == ["id": "10"])
        #expect(fields["summary"] as? String == "Crash on launch")
        #expect((fields["priority"] as? [String: String]) == ["id": "2"])
        #expect(fields["labels"] as? [String] == ["ios"])
        #expect((fields["components"] as? [[String: String]]) == [["id": "5"]])
        #expect((fields["assignee"] as? [String: String]) == ["accountId": "acc-1"])
        #expect((fields["parent"] as? [String: String]) == ["key": "APP-1"])
        #expect(fields["duedate"] as? String == "2026-12-01")
        #expect(fields["customfield_10016"] as? Double == 3)
        #expect(JiraADF.plainText(from: fields["description"]) == "Steps:\n• open\n• crash")
    }

    @Test func createOmitsWhatWasNotFilledIn() async throws {
        let mock = MockJira { _ in MockReply(status: 201, json: #"{"key":"APP-1"}"#) }

        _ = try await mock.client.create(JiraNewIssue(projectKey: "APP", issueTypeID: "10", summary: "Bare"))

        let fields = try #require(mock.requests.first?.fields)
        #expect(Set(fields.keys) == ["project", "issuetype", "summary"])
    }

    @Test func createSurfacesJiraValidationMessages() async {
        let mock = MockJira { _ in
            MockReply(status: 400, json: #"{"errorMessages":[],"errors":{"summary":"You must specify a summary of the issue."}}"#)
        }

        await #expect(throws: JiraError.self) {
            _ = try await mock.client.create(JiraNewIssue(projectKey: "APP", issueTypeID: "10", summary: ""))
        }
    }

    @Test func editSendsOnlyTheChangedFieldsAndClearsWithNull() async throws {
        let mock = MockJira { _ in MockReply(status: 204) }

        try await mock.client.edit(key: "APP-7", [
            .summary("New title"),
            .priority(id: "1"),
            .labels(["a", "b"]),
            .components(ids: ["5", "6"]),
            .dueDate(nil),
            .parent("APP-1"),
            .storyPoints(fieldID: "customfield_10016", 5),
            .description("Hello")
        ])

        let sent = try #require(mock.requests.first)
        #expect(sent.method == "PUT")
        #expect(sent.path == "/rest/api/3/issue/APP-7")
        let fields = try #require(sent.fields)
        #expect(fields["summary"] as? String == "New title")
        #expect((fields["priority"] as? [String: String]) == ["id": "1"])
        #expect(fields["labels"] as? [String] == ["a", "b"])
        #expect((fields["components"] as? [[String: String]]) == [["id": "5"], ["id": "6"]])
        #expect(fields["duedate"] is NSNull)
        #expect((fields["parent"] as? [String: String]) == ["key": "APP-1"])
        #expect(fields["customfield_10016"] as? Double == 5)
        #expect(JiraADF.plainText(from: fields["description"]) == "Hello")
    }

    @Test func editWithNoUpdatesSendsNothing() async throws {
        let mock = MockJira { _ in MockReply(status: 204) }
        try await mock.client.edit(key: "APP-7", [])
        #expect(mock.requests.isEmpty)
    }

    @Test func emptyDescriptionClearsIt() {
        #expect(JiraFieldUpdate.description("  \n").value == .null)
    }

    @Test func authorizationFailureIsReportedAsUnauthorized() async {
        let mock = MockJira { _ in MockReply(status: 401) }

        await #expect(throws: JiraError.self) { _ = try await mock.client.projects() }
        #expect(mock.requests.first?.headers["Authorization"]?.hasPrefix("Basic ") == true)
    }
}

struct JiraLookupTests {
    @Test func assignableUsersSkipAppsAndInactiveAccounts() async throws {
        let mock = MockJira { _ in
            MockReply(json: """
            [{"accountId":"a1","displayName":"Ana","accountType":"atlassian","active":true,"avatarUrls":{"48x48":"https://x.test/a.png"}},
             {"accountId":"a2","displayName":"Bot","accountType":"app","active":true},
             {"accountId":"a3","displayName":"Gone","accountType":"atlassian","active":false}]
            """)
        }

        let users = try await mock.client.searchAssignableUsers(query: "an a&b", projectKey: "APP")

        #expect(users.map(\.accountID) == ["a1"])
        #expect(users[0].avatarURL?.absoluteString == "https://x.test/a.png")
        let sent = try #require(mock.requests.first)
        #expect(sent.path == "/rest/api/3/user/assignable/search")
        #expect(sent.query["query"] == "an a&b")
        #expect(sent.query["project"] == "APP")
    }

    @Test func assignableUsersForAnIssueAskByIssueKey() async throws {
        let mock = MockJira { _ in MockReply(json: "[]") }
        _ = try await mock.client.searchAssignableUsers(query: "", issueKey: "APP-3")
        #expect(mock.requests.first?.query["issueKey"] == "APP-3")
    }

    @Test func userSearchHitsTheSiteWideEndpoint() async throws {
        let mock = MockJira { _ in MockReply(json: #"[{"accountId":"a1","displayName":"Ana","emailAddress":"ana@acme.test"}]"#) }
        let users = try await mock.client.searchUsers(query: "ana")
        #expect(users.first?.email == "ana@acme.test")
        #expect(mock.requests.first?.path == "/rest/api/3/user/search")
    }

    @Test func prioritiesAndComponentsReadIdAndName() async throws {
        let mock = MockJira { sent in
            sent.path.hasSuffix("/components")
                ? MockReply(json: #"[{"id":"5","name":"API"}]"#)
                : MockReply(json: #"[{"id":"1","name":"Highest"},{"id":"2","name":"High"}]"#)
        }

        let priorities = try await mock.client.priorities()
        let components = try await mock.client.components(projectKey: "APP")

        #expect(priorities.map(\.label) == ["Highest", "High"])
        #expect(components == [JiraFieldOption(id: "5", label: "API")])
    }

    @Test func labelsListAllOrSuggestForAQuery() async throws {
        let mock = MockJira { sent in
            sent.path == "/rest/api/3/label"
                ? MockReply(json: #"{"isLast":true,"values":["ios","mac"]}"#)
                : MockReply(json: #"{"results":[{"value":"ios","displayName":"<b>io</b>s"}]}"#)
        }

        let all = try await mock.client.labels()
        let some = try await mock.client.labels(query: "io")

        #expect(all == ["ios", "mac"])
        #expect(some == ["ios"])
        #expect(mock.requests[1].query["fieldName"] == "labels")
        #expect(mock.requests[1].query["fieldValue"] == "io")
    }

    @Test func storyPointsFieldIsFoundByName() async throws {
        let mock = MockJira { _ in
            MockReply(json: """
            [{"id":"summary","name":"Summary","custom":false,"schema":{"type":"string"}},
             {"id":"customfield_10016","name":"Story point estimate","custom":true,"schema":{"type":"number"}},
             {"id":"customfield_10020","name":"Sprint","custom":true,"schema":{"type":"array"}}]
            """)
        }

        let fields = try await mock.client.fields()

        #expect(JiraFieldInfo.storyPointsID(in: fields) == "customfield_10016")
        #expect(JiraFieldInfo.storyPointsID(in: []) == nil)
    }

    @Test func issueDecodingReadsPlanningFields() throws {
        let raw = try JSONSerialization.jsonObject(with: Data("""
        {"key":"APP-9","fields":{"summary":"S","status":{"id":"3","name":"Doing","statusCategory":{"key":"indeterminate"}},
         "duedate":"2026-12-01","components":[{"name":"API"}],"customfield_10016":5.0,
         "parent":{"key":"APP-1","fields":{"summary":"Epic"}}}}
        """.utf8)) as! [String: Any]

        let issue = try #require(JiraClient.issue(from: raw, storyPointsField: "customfield_10016"))

        #expect(issue.statusID == "3")
        #expect(issue.dueDate == "2026-12-01")
        #expect(issue.components == ["API"])
        #expect(issue.storyPoints == 5)
        #expect(issue.parentKey == "APP-1" && issue.parentSummary == "Epic")
    }
}

struct JiraADFBuilderTests {
    private func roundTrip(_ text: String) -> String {
        JiraADF.plainText(from: JiraADF.document(from: text))
    }

    @Test func paragraphsAndLineBreaksRoundTrip() {
        #expect(roundTrip("First line\nsecond line") == "First line\nsecond line")

        // `plainText` writes paragraphs on consecutive lines, so a blank line
        // is the one thing the way back cannot reproduce.
        #expect(roundTrip("one\n\ntwo") == "one\ntwo")
    }

    @Test func listsRoundTripIncludingNesting() {
        let text = "Todo:\n• one\n  • inner\n• two\n1. first\n2. second"
        #expect(roundTrip(text) == text)
    }

    @Test func markdownKeepsItsFormatting() throws {
        let doc = JiraADF.document(from: "# Title\n\nSome **bold** text")
        let content = try #require(doc["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "heading")
        #expect(JiraADF.plainText(from: doc) == "Title\nSome bold text")
    }

    @Test func dashAndStarBulletsBecomeBulletLists() {
        #expect(roundTrip("- a\n* b") == "• a\n• b")
    }

    @Test func fencesBecomeCodeBlocks() throws {
        let doc = JiraADF.document(from: "Run:\n```\nswift build\n```")
        let content = try #require(doc["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["paragraph", "codeBlock"])
        #expect(JiraADF.plainText(from: doc) == "Run:\nswift build")
    }

    @Test func documentIsAValidEnvelopeAndNeverHasEmptyTextNodes() throws {
        let doc = JiraADF.document(from: "a\n\n\nb")
        #expect(doc["type"] as? String == "doc")
        #expect(doc["version"] as? Int == 1)

        let data = try JSONSerialization.data(withJSONObject: JiraADF.document(from: ""))
        #expect(String(data: data, encoding: .utf8)?.contains("\"text\":\"\"") == false)
        #expect(roundTrip("a\n\n\nb") == "a\nb")
    }
}
