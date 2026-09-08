//
//  JiraViewModel.swift
//  GitHalls
//

import Foundation
import Observation

/// Jira state, kept deliberately apart from `RepositoryViewModel`: Jira is not
/// git. The two meet in exactly one place — the issue window, which holds both
/// and asks the repository to create a branch.
///
/// The board is one query at a time: a preset or one the user saved. The result
/// is grouped into columns by status, and a text filter narrows the cards
/// without asking Jira again.
@Observable
@MainActor
final class JiraViewModel {
    /// A sprint fits; a backlog does not, and shouldn't be a board.
    private static let searchLimit = 100

    private(set) var queries: [JiraQuery] = JiraQueryPresets.all

    private(set) var selectedQuery: JiraQuery = JiraQueryPresets.default

    /// Changes whenever the board should run again — a different query, or the
    /// same one edited. The board watches it with `.task(id:)`, so the reload
    /// belongs to the view's lifetime and not to a stray task from a setter.
    private(set) var reloadToken = UUID()

    /// Narrows what is already on the board; never asks Jira.
    var filterText = ""

    var isLoading = false
    var errorMessage: String?

    /// True once a search has run and returned — not before.
    var hasSearched = false

    /// The last result, unfiltered, so a filter change costs no request.
    private var groups: [JiraIssueGroup] = []

    /// Same guard the git loads use: a slow answer to a query the user has
    /// moved on from must not replace what is on screen.
    private var searchToken = UUID()

    init() {
        queries = JiraQueryPresets.combine(custom: JiraQueryStore.load())

        if let remembered = queries.first(where: { $0.id == JiraQueryStore.selectedID }) {
            selectedQuery = remembered
        }
    }

    var isConfigured: Bool { JiraCredentialsStore.isConfigured }

    /// The board: one column per status, holding only the cards that pass the filter.
    var columns: [JiraIssueGroup] { JiraIssueGrouping.filter(groups, by: filterText) }

    /// How many cards the query returned, before any filter.
    var issueCount: Int { groups.reduce(0) { $0 + $1.count } }

    var shownCount: Int { columns.reduce(0) { $0 + $1.count } }

    // MARK: - Queries

    func select(_ query: JiraQuery) {
        guard query.id != selectedQuery.id else { return }

        selectedQuery = query
        JiraQueryStore.selectedID = query.id
        reloadToken = UUID()
    }

    func addQuery(name: String, jql: String) {
        let query = JiraQuery(name: name.trimmingCharacters(in: .whitespaces),
                              jql: jql.trimmingCharacters(in: .whitespaces))
        queries.append(query)
        JiraQueryStore.save(queries)
        select(query)
    }

    func updateQuery(_ query: JiraQuery, name: String, jql: String) {
        guard !query.isBuiltIn, let index = queries.firstIndex(where: { $0.id == query.id }) else { return }

        queries[index].name = name.trimmingCharacters(in: .whitespaces)
        queries[index].jql = jql.trimmingCharacters(in: .whitespaces)
        JiraQueryStore.save(queries)

        if selectedQuery.id == query.id {
            // Same query, new text: the id did not change, so the board needs
            // telling that its JQL did.
            selectedQuery = queries[index]
            reloadToken = UUID()
        }
    }

    func removeQuery(_ query: JiraQuery) {
        guard !query.isBuiltIn else { return }

        queries.removeAll { $0.id == query.id }
        JiraQueryStore.save(queries)

        if selectedQuery.id == query.id {
            select(JiraQueryPresets.default)
        }
    }

    // MARK: - Search

    func refresh() async {
        guard let credentials = JiraCredentialsStore.current else {
            errorMessage = "Jira is not connected. Open Settings to connect an account."
            return
        }

        let token = UUID()
        searchToken = token
        isLoading = true

        do {
            let issues = try await JiraClient(credentials: credentials)
                .search(jql: selectedQuery.jql, limit: Self.searchLimit)

            guard searchToken == token else { return }

            groups = JiraIssueGrouping.byStatus(issues)
            hasSearched = true
            errorMessage = nil
        } catch {
            guard searchToken == token else { return }
            errorMessage = error.localizedDescription
        }

        if searchToken == token { isLoading = false }
    }

    /// Called when the account is connected or disconnected in Settings.
    func accountChanged() {
        guard !isConfigured else { return }

        groups = []
        hasSearched = false
        errorMessage = nil
    }

    /// Drops what is on the board so the next `.task(id:)` fetches it again.
    func invalidate() {
        reloadToken = UUID()
    }

    // MARK: - One issue

    /// The full issue, description included. The window that asked owns the answer.
    func fetchIssue(key: String) async throws -> JiraIssue {
        guard let credentials = JiraCredentialsStore.current else { throw JiraCredentialsError.missing }

        return try await JiraClient(credentials: credentials).issue(key: key)
    }

    func browseURL(for issue: JiraIssue) -> URL? {
        guard let credentials = JiraCredentialsStore.current else { return nil }

        return JiraClient(credentials: credentials).browseURL(for: issue.key)
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
