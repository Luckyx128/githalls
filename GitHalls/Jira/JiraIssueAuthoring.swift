//
//  JiraIssueAuthoring.swift
//  GitHalls
//

import Foundation

/// What the create and edit screens need from Jira. A protocol so the views and
/// their view models are written and tested without a network; `JiraClient`
/// conforms (Atlas's calls, see Docs/JIRA_API.md), a stub stands in until then.
protocol JiraIssueAuthoring: Sendable {
    func projects() async throws -> [JiraProject]
    func issueTypes(projectKey: String) async throws -> [JiraIssueType]
    func createFields(projectKey: String, issueTypeID: String) async throws -> [JiraCreateField]
    func searchAssignableUsers(query: String, projectKey: String) async throws -> [JiraUser]
    func priorities() async throws -> [JiraFieldOption]
    /// Teams for a Team field; pass the field's `autoCompleteURL`.
    func teams(query: String, autoCompleteURL: String?) async throws -> [JiraFieldOption]
    /// The new issue's key.
    func create(_ issue: JiraNewIssue) async throws -> String
}

extension JiraClient: JiraIssueAuthoring {}

/// Where the screens get their authoring backend. One line to change when the
/// real client conforms.
enum JiraAuthoringFactory {
    static func make() -> any JiraIssueAuthoring {
        if let credentials = JiraCredentialsStore.current { JiraClient(credentials: credentials) } else { UnconfiguredAuthoring() }
    }
}

/// What the screens talk to before an account is connected: every call says so.
struct UnconfiguredAuthoring: JiraIssueAuthoring {
    private var error: Error { JiraCredentialsError.missing }

    func projects() async throws -> [JiraProject] { throw error }
    func issueTypes(projectKey: String) async throws -> [JiraIssueType] { throw error }
    func createFields(projectKey: String, issueTypeID: String) async throws -> [JiraCreateField] { throw error }
    func searchAssignableUsers(query: String, projectKey: String) async throws -> [JiraUser] { throw error }
    func priorities() async throws -> [JiraFieldOption] { throw error }
    func teams(query: String, autoCompleteURL: String?) async throws -> [JiraFieldOption] { throw error }
    func create(_ issue: JiraNewIssue) async throws -> String { throw error }
}

/// Canned answers for previews, tests and the time before the real client lands.
struct StubJiraAuthoring: JiraIssueAuthoring {
    var projects: [JiraProject] = [JiraProject(id: "1", key: "DEMO", name: "Demo")]
    var types: [JiraIssueType] = [
        JiraIssueType(id: "10", name: "Task", isSubtask: false, hierarchyLevel: 0),
        JiraIssueType(id: "11", name: "Sub-task", isSubtask: true, hierarchyLevel: -1)
    ]
    var fields: [JiraCreateField] = []
    var users: [JiraUser] = []
    var teams: [JiraFieldOption] = []
    var failure: Error?

    func projects() async throws -> [JiraProject] { projects }
    func issueTypes(projectKey: String) async throws -> [JiraIssueType] { types }
    func createFields(projectKey: String, issueTypeID: String) async throws -> [JiraCreateField] { fields }

    func searchAssignableUsers(query: String, projectKey: String) async throws -> [JiraUser] {
        users.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    func priorities() async throws -> [JiraFieldOption] {
        ["Highest", "High", "Medium", "Low", "Lowest"].enumerated().map {
            JiraFieldOption(id: String($0.offset + 1), label: $0.element)
        }
    }

    func teams(query: String, autoCompleteURL: String?) async throws -> [JiraFieldOption] { teams }

    func create(_ issue: JiraNewIssue) async throws -> String {
        if let failure { throw failure }
        return "\(issue.projectKey)-1"
    }
}
