//
//  JiraViewModel.swift
//  GitHalls
//

import Foundation
import Observation

@Observable
@MainActor
final class JiraViewModel {
    var jql: String = "assignee = currentUser() ORDER BY updated DESC"
    var issues: [JiraIssue] = []
    var selectedIssueID: JiraIssue.ID?
    var isLoading = false
    var errorMessage: String?

    var isConfigured: Bool { JiraCredentialsStore.isConfigured }

    var selectedIssue: JiraIssue? {
        issues.first { $0.id == selectedIssueID }
    }

    struct IssueGroup: Identifiable {
        let status: String
        let category: String
        let issues: [JiraIssue]
        var id: String { status }
    }

    var issuesByStatus: [IssueGroup] {
        var order: [String] = []
        var groups: [String: [JiraIssue]] = [:]
        var categoryByStatus: [String: String] = [:]
        for issue in issues {
            if groups[issue.status] == nil {
                order.append(issue.status)
                groups[issue.status] = []
                categoryByStatus[issue.status] = issue.statusCategory
            }
            groups[issue.status]?.append(issue)
        }

        let sortedOrder = order.sorted { lhs, rhs in
            let lhsDone = categoryByStatus[lhs] == "done"
            let rhsDone = categoryByStatus[rhs] == "done"
            guard lhsDone != rhsDone else { return false } // mantém ordem original entre iguais (sort é estável)
            return !lhsDone // não-"done" vem antes
        }

        return sortedOrder.map { status in
            IssueGroup(status: status, category: categoryByStatus[status] ?? "indeterminate", issues: groups[status] ?? [])
        }
    }

    func refresh() async {
        guard let credentials = JiraCredentialsStore.current else {
            errorMessage = "Jira not configured. Open Settings to connect."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            issues = try await JiraClient(credentials: credentials).search(jql: jql)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func suggestedBranchName(for issue: JiraIssue) -> String {
        let slug = issue.summary
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let truncatedSlug = String(slug.prefix(40))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return truncatedSlug.isEmpty ? issue.key : "\(issue.key)-\(truncatedSlug)"
    }
}
