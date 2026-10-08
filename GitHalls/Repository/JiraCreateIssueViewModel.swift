//
//  JiraCreateIssueViewModel.swift
//  GitHalls
//

import Foundation
import Observation

/// What control a createmeta field gets. One place decides it, so the sheet and
/// the payload agree.
enum JiraFieldInput: Equatable {
    case text, markdown, number, date, dateTime, user, select, multiSelect, labels, duration, team
}

/// The state behind the Create Issue sheet. Project and issue type decide which
/// fields Jira wants (createmeta), so choosing either reloads the form. Every
/// field createmeta marks `required` gets an input, is checked before anything
/// is sent, and shows Jira's own message next to it if Jira still refuses.
@Observable
@MainActor
final class JiraCreateIssueViewModel {
    /// Fields with a built-in home on this view model.
    static let standardFieldKeys: Set<String> = [
        "project", "issuetype", "summary", "description", "priority", "labels",
        "assignee", "reporter", "parent", "components", "duedate", "attachment"
    ]

    private let authoring: any JiraIssueAuthoring

    private(set) var projects: [JiraProject] = []
    private(set) var issueTypes: [JiraIssueType] = []
    private(set) var fields: [JiraCreateField] = []
    private(set) var priorities: [JiraFieldOption] = []

    var selectedProject: JiraProject?
    var selectedType: JiraIssueType?

    var summary = ""
    var descriptionMarkdown = ""
    var priorityID: String?
    var labelsText = ""
    var assignee: JiraUser?
    var parentKey = ""
    var dueDate: Date?

    /// Components picked, by id.
    var componentIDs: Set<String> = []

    /// Single-valued dynamic fields: text, a number, an option or team id,
    /// `yyyy-MM-dd`, a duration like "2h 30m".
    var extraValues: [String: String] = [:]

    /// Multi-valued ones: option ids.
    var extraSelections: [String: Set<String>] = [:]

    /// People for user and multi-user fields, by field key.
    var extraUsers: [String: [JiraUser]] = [:]

    /// Jira's (or our own) message, by field key.
    private(set) var fieldErrors: [String: String] = [:]

    private(set) var isLoading = false
    private(set) var isSubmitting = false

    /// What is not about one field: a failed load, a network error.
    var errorMessage: String?

    private let preferredProjectKey: String?

    private static let lastProjectKeyDefaults = "jira.createIssue.lastProjectKey"

    static var lastProjectKey: String? {
        get { UserDefaults.standard.string(forKey: lastProjectKeyDefaults) }
        set { UserDefaults.standard.set(newValue, forKey: lastProjectKeyDefaults) }
    }

    init(authoring: any JiraIssueAuthoring, projectKey: String? = nil) {
        self.authoring = authoring
        // The board's project when there is one; otherwise the last one used.
        self.preferredProjectKey = projectKey ?? Self.lastProjectKey
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
        extraSelections = [:]
        extraUsers = [:]
        fieldErrors = [:]
        componentIDs = []
        guard let project = selectedProject, let type else { return }

        do {
            fields = try await authoring.createFields(projectKey: project.key, issueTypeID: type.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func findUsers(_ query: String) async -> [JiraUser] {
        guard let project = selectedProject else { return [] }
        return (try? await authoring.searchAssignableUsers(query: query, projectKey: project.key)) ?? []
    }

    func findTeams(_ query: String, for field: JiraCreateField) async -> [JiraFieldOption] {
        (try? await authoring.teams(query: query, autoCompleteURL: field.autoCompleteURL)) ?? []
    }

    // MARK: - Fields

    private func field(_ key: String) -> JiraCreateField? { fields.first { $0.key == key } }

    /// Jira marks a field required in createmeta; one with a default value
    /// fills itself, so it is not asked for.
    func isRequired(_ key: String) -> Bool {
        guard let field = field(key) else { return key == "summary" }
        return field.required && (!field.hasDefault || key == "summary")
    }

    func isShown(_ key: String) -> Bool { fields.isEmpty || field(key) != nil }

    var supportsParent: Bool { (selectedType?.isSubtask ?? false) || field("parent") != nil }
    var parentRequired: Bool { isRequired("parent") || (selectedType?.isSubtask ?? false) }

    /// Priorities for the picker: the field's own allowed values when createmeta
    /// lists them, the site's list otherwise.
    var priorityOptions: [JiraFieldOption] {
        let allowed = field("priority")?.allowed ?? []
        return allowed.isEmpty ? priorities : allowed
    }

    var componentOptions: [JiraFieldOption] { field("components")?.allowed ?? [] }

    /// Everything beyond the built-in fields that Jira insists on.
    var dynamicFields: [JiraCreateField] {
        fields.filter { $0.required && !$0.hasDefault && !Self.standardFieldKeys.contains($0.key) }
    }

    static func input(for field: JiraCreateField) -> JiraFieldInput {
        switch field.kind {
        case .adf: .markdown
        case .number: .number
        case .date: .date
        case .dateTime: .dateTime
        case .user: .user
        case .userList: .user
        case .team: .team
        case .timeTracking: .duration
        case .labels: .labels
        case .multiOption, .components: .multiSelect
        case .option, .priority: .select
        case .string: field.allowed.isEmpty ? .text : .select
        case .other: field.allowed.isEmpty ? .text : .select
        }
    }

    // MARK: - Validation

    /// The first thing wrong with each field, by key. Empty means ready to send.
    var problems: [String: String] {
        var found: [String: String] = [:]

        func need(_ key: String, _ isEmpty: Bool) {
            if isEmpty, isRequired(key) { found[key] = "Required." }
        }

        if selectedProject == nil { found["project"] = "Required." }
        if selectedType == nil { found["issuetype"] = "Required." }
        if trimmed(summary).isEmpty { found["summary"] = "Required." }
        need("description", trimmed(descriptionMarkdown).isEmpty)
        need("priority", priorityID == nil)
        need("labels", Self.labels(from: labelsText).isEmpty)
        need("components", componentIDs.isEmpty)
        need("assignee", assignee == nil)
        need("duedate", dueDate == nil)
        if parentRequired, trimmed(parentKey).isEmpty { found["parent"] = "Required." }

        for field in dynamicFields {
            let text = trimmed(extraValues[field.key] ?? "")
            switch Self.input(for: field) {
            case .multiSelect:
                if (extraSelections[field.key] ?? []).isEmpty { found[field.key] = "Required." }
            case .user:
                if (extraUsers[field.key] ?? []).isEmpty { found[field.key] = "Required." }
            case .duration:
                if text.isEmpty { found[field.key] = "Required." }
                else if JiraDuration.seconds(from: text) == nil { found[field.key] = "Use a format like 2h 30m." }
            case .number:
                if text.isEmpty { found[field.key] = "Required." }
                else if Double(text) == nil { found[field.key] = "Enter a number." }
            default:
                if text.isEmpty { found[field.key] = "Required." }
            }
        }
        return found
    }

    /// Names of what still blocks Create, for the footer.
    var missing: [String] {
        let names = problems.keys.sorted().map { key -> String in
            switch key {
            case "project": "Project"
            case "issuetype": "Issue type"
            case "summary": "Summary"
            case "description": "Description"
            case "duedate": "Due date"
            default: field(key)?.name ?? key.capitalized
            }
        }
        return names
    }

    var canSubmit: Bool { problems.isEmpty && !isSubmitting && !isLoading }

    // MARK: - Payload

    func draft() -> JiraNewIssue? {
        guard let project = selectedProject, let type = selectedType else { return nil }

        let description = trimmed(descriptionMarkdown)
        let parent = trimmed(parentKey)
        let labels = Self.labels(from: labelsText)

        return JiraNewIssue(
            projectKey: project.key,
            issueTypeID: type.id,
            summary: trimmed(summary),
            description: description.isEmpty ? nil : description,
            priorityID: priorityID,
            labels: labels,
            componentIDs: componentOptions.map(\.id).filter(componentIDs.contains),
            assigneeAccountID: assignee?.accountID,
            parentKey: parent.isEmpty ? nil : parent,
            dueDate: dueDate.map(Self.dayString),
            extra: dynamicFields.compactMap(extraUpdate)
        )
    }

    /// The new issue's key, or nil with the reason set — next to the field when
    /// Jira named one.
    func submit() async -> String? {
        let current = problems
        guard current.isEmpty else {
            fieldErrors = current
            return nil
        }
        guard !isSubmitting, let draft = draft() else { return nil }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let key = try await authoring.create(draft)
            Self.lastProjectKey = draft.projectKey
            errorMessage = nil
            fieldErrors = [:]
            return key
        } catch JiraError.fieldErrors(let errors) {
            // Jira keys these by field id; one it names that the sheet has no
            // row for would vanish, so it goes to the general message instead.
            var unplaced: [String] = []
            for (key, message) in errors {
                if key == "summary" || field(key) != nil || (fields.isEmpty && Self.standardFieldKeys.contains(key)) {
                    fieldErrors[key] = message
                } else {
                    unplaced.append(message)
                }
            }
            errorMessage = unplaced.isEmpty ? nil : unplaced.joined(separator: " ")
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Typing in a field retires the message about it.
    func clearError(_ key: String) {
        fieldErrors[key] = nil
    }

    func extraUpdate(for field: JiraCreateField) -> JiraFieldUpdate? {
        let text = trimmed(extraValues[field.key] ?? "")
        let key = field.key

        switch Self.input(for: field) {
        case .number:
            return Double(text).map { .custom(key, .number($0)) }
        case .select:
            // A priority or option is `{"id": …}`; a plain string that merely
            // has allowed values would be `{"value": …}` — createmeta ids work for both.
            return text.isEmpty ? nil : .custom(key, .object(["id": .string(text)]))
        case .multiSelect:
            let ids = field.allowed.map(\.id).filter((extraSelections[key] ?? []).contains)
            return ids.isEmpty ? nil : .custom(key, .array(ids.map { .object(["id": .string($0)]) }))
        case .user:
            let users = extraUsers[key] ?? []
            guard !users.isEmpty else { return nil }
            if field.kind == .userList {
                return .custom(key, .array(users.map { .object(["accountId": .string($0.accountID)]) }))
            }
            return .custom(key, .object(["accountId": .string(users[0].accountID)]))
        case .labels:
            let labels = Self.labels(from: text)
            return labels.isEmpty ? nil : .custom(key, .array(labels.map(JiraJSON.string)))
        case .duration:
            return text.isEmpty ? nil : .custom(key, .object(["originalEstimate": .string(text)]))
        case .team:
            return text.isEmpty ? nil : .custom(key, .string(text))
        case .markdown:
            let value = JiraJSON(foundation: JiraMarkdownADF.document(from: text))
            return text.isEmpty ? nil : value.map { .custom(key, $0) }
        case .date, .dateTime, .text:
            return text.isEmpty ? nil : .custom(key, .string(text))
        }
    }

    // MARK: - Helpers

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func labels(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func dayString(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}
