//
//  JiraCreateIssueViewModel.swift
//  GitHalls
//

import Foundation
import Observation

/// The state behind the Create Issue sheet. Project and issue type drive which
/// fields Jira wants (createmeta), so choosing either reloads the form; the
/// fields every issue has are first-class properties and the rest — whatever the
/// project marks required — live in `extraValues`, keyed by field.
@Observable
@MainActor
final class JiraCreateIssueViewModel {
    /// Fields the sheet draws itself; they never appear among the dynamic ones.
    static let standardFieldKeys: Set<String> = [
        "project", "issuetype", "summary", "description", "priority", "labels",
        "assignee", "reporter", "parent", "components", "duedate", "attachment"
    ]

    private let authoring: any JiraIssueAuthoring

    private(set) var projects: [JiraProject] = []
    private(set) var issueTypes: [JiraIssueType] = []
    private(set) var fields: [JiraCreateField] = []
    private(set) var priorities: [JiraFieldOption] = []
    private(set) var userResults: [JiraUser] = []

    var selectedProject: JiraProject?
    var selectedType: JiraIssueType?

    var summary = ""
    var descriptionMarkdown = ""
    var priorityID: String?
    var labelsText = ""
    var assignee: JiraUser?
    var parentKey = ""
    var dueDate: Date?

    /// Dynamic required fields: text for strings and numbers, an option id for
    /// pickers, `yyyy-MM-dd` for dates.
    var extraValues: [String: String] = [:]

    private(set) var isLoading = false
    private(set) var isSubmitting = false
    var errorMessage: String?

    private var userSearchToken = UUID()

    init(authoring: any JiraIssueAuthoring, projectKey: String? = nil) {
        self.authoring = authoring
        // The board's project when there is one; otherwise the last one used.
        self.preferredProjectKey = projectKey ?? Self.lastProjectKey
    }

    private let preferredProjectKey: String?

    private static let lastProjectKeyDefaults = "jira.createIssue.lastProjectKey"

    static var lastProjectKey: String? {
        get { UserDefaults.standard.string(forKey: lastProjectKeyDefaults) }
        set { UserDefaults.standard.set(newValue, forKey: lastProjectKeyDefaults) }
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let loadedProjects = authoring.projects()
            async let loadedPriorities = authoring.priorities()
            projects = try await loadedProjects
            priorities = (try? await loadedPriorities) ?? []

            let project = projects.first { $0.key == preferredProjectKey } ?? projects.first
            await select(project: project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(project: JiraProject?) async {
        selectedProject = project
        selectedType = nil
        issueTypes = []
        fields = []
        guard let project else { return }

        do {
            issueTypes = try await authoring.issueTypes(projectKey: project.key)
            // A plain task first: sub-tasks need a parent the user hasn't named.
            let type = issueTypes.first { $0.name == "Task" && !$0.isSubtask }
                ?? issueTypes.first { !$0.isSubtask }
                ?? issueTypes.first
            await select(type: type)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(type: JiraIssueType?) async {
        selectedType = type
        fields = []
        extraValues = [:]
        guard let project = selectedProject, let type else { return }

        do {
            fields = try await authoring.createFields(projectKey: project.key, issueTypeID: type.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func searchUsers(_ query: String) async {
        guard let project = selectedProject else { return }

        let token = UUID()
        userSearchToken = token
        let found = (try? await authoring.searchAssignableUsers(query: query, projectKey: project.key)) ?? []
        if userSearchToken == token { userResults = found }
    }

    // MARK: - Fields

    private func has(_ key: String) -> Bool { fields.contains { $0.key == key } }

    var supportsParent: Bool { (selectedType?.isSubtask ?? false) || has("parent") }
    var parentRequired: Bool { fields.first { $0.key == "parent" }?.required ?? (selectedType?.isSubtask ?? false) }
    var supportsLabels: Bool { fields.isEmpty || has("labels") }
    var supportsPriority: Bool { fields.isEmpty || has("priority") }

    /// Required fields the sheet has no built-in control for.
    var dynamicFields: [JiraCreateField] {
        fields.filter { $0.required && !$0.hasDefault && !Self.standardFieldKeys.contains($0.key) }
    }

    /// What still blocks the Create button, for the user to read.
    var missing: [String] {
        var names: [String] = []
        if selectedProject == nil { names.append("Project") }
        if selectedType == nil { names.append("Issue type") }
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { names.append("Summary") }
        if parentRequired, parentKey.trimmingCharacters(in: .whitespaces).isEmpty { names.append("Parent") }
        for field in dynamicFields where (extraValues[field.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            names.append(field.name)
        }
        return names
    }

    var canSubmit: Bool { missing.isEmpty && !isSubmitting && !isLoading }

    // MARK: - Submit

    func draft() -> JiraNewIssue? {
        guard let project = selectedProject, let type = selectedType else { return nil }

        let description = descriptionMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = parentKey.trimmingCharacters(in: .whitespaces)

        return JiraNewIssue(
            projectKey: project.key,
            issueTypeID: type.id,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.isEmpty ? nil : description,
            priorityID: priorityID,
            labels: Self.labels(from: labelsText),
            assigneeAccountID: assignee?.accountID,
            parentKey: parent.isEmpty ? nil : parent,
            dueDate: dueDate.map(Self.dayString),
            extra: dynamicFields.compactMap(extraUpdate)
        )
    }

    /// The new issue's key, or nil with `errorMessage` set.
    func submit() async -> String? {
        guard canSubmit, let draft = draft() else { return nil }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let key = try await authoring.create(draft)
            Self.lastProjectKey = draft.projectKey
            errorMessage = nil
            return key
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func extraUpdate(for field: JiraCreateField) -> JiraFieldUpdate? {
        let raw = (extraValues[field.key] ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }

        switch field.kind {
        case .number:
            guard let number = Double(raw) else { return nil }
            return .custom(field.key, .number(number))
        case .option, .priority:
            return .custom(field.key, .object(["id": .string(raw)]))
        case .user:
            return .custom(field.key, .object(["accountId": .string(raw)]))
        default:
            return .custom(field.key, .string(raw))
        }
    }

    static func labels(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func dayString(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}
