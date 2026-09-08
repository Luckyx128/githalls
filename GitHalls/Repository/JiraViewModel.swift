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

    /// The moves already fetched, and the status they were fetched for. Which
    /// moves an issue can make is a function of where it stands, so a card that
    /// has moved has to ask again — hence the status alongside, not just the key.
    private var transitionsCache: [String: (status: String, transitions: [JiraTransition])] = [:]

    /// Issues with a write in flight: one at a time each, and the board greys them.
    private(set) var busyIssues: Set<String> = []

    /// The account id an assign needs. Nil means "not asked yet", which is why a
    /// menu reads it rather than awaiting it.
    private(set) var myAccountID: String?

    /// The Task and not the value, so two windows asking at once make one request.
    private var myselfTask: Task<(accountID: String, displayName: String), Error>?

    /// What the last write did, or why it didn't. Not `errorMessage`: that one
    /// is the board's empty state, which is hidden whenever there are columns —
    /// precisely when a write happens.
    var actionMessage: String?
    var actionFailed = false

    /// Which issue the message is about, so a window only shows the one that
    /// concerns it.
    private(set) var actionIssueKey: String?

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
            transitionsCache = [:]
            hasSearched = true
            errorMessage = nil

            // Learn who "me" is alongside the first search, so a card can tell
            // an issue that is already yours without stopping to ask. Not
            // awaited: the board is loaded, and this only decides a label.
            if myAccountID == nil {
                Task { try? await self.myself() }
            }
        } catch {
            guard searchToken == token else { return }
            errorMessage = error.localizedDescription
        }

        if searchToken == token { isLoading = false }
    }

    /// Called when the account is connected or disconnected in Settings.
    func accountChanged() {
        transitionsCache = [:]
        myselfTask = nil
        myAccountID = nil

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

    /// The board's copy of an issue, for a window that wants to follow it.
    func boardIssue(for key: String) -> JiraIssue? {
        groups.lazy.flatMap(\.issues).first { $0.key == key }
    }

    // MARK: - Acting on an issue

    /// Who the credentials belong to. Asked once: /myself does not change under
    /// us. A failed attempt is dropped, or one flaky call would leave assigning
    /// broken for the rest of the session.
    @discardableResult
    func myself() async throws -> (accountID: String, displayName: String) {
        if let myselfTask { return try await myselfTask.value }

        guard let credentials = JiraCredentialsStore.current else { throw JiraCredentialsError.missing }

        let task = Task { try await JiraClient(credentials: credentials).myself() }
        myselfTask = task

        do {
            let me = try await task.value
            myAccountID = me.accountID
            return me
        } catch {
            if myselfTask == task { myselfTask = nil }
            throw error
        }
    }

    /// The moves this issue can make. One request per card, kept only for as
    /// long as the issue stays where it was: a card that moved has a different
    /// set of moves, and a stale menu is worse than a second request.
    func transitions(for issue: JiraIssue) async throws -> [JiraTransition] {
        if let cached = transitionsCache[issue.key], cached.status == issue.status {
            return cached.transitions
        }

        guard let credentials = JiraCredentialsStore.current else { throw JiraCredentialsError.missing }

        let transitions = try await JiraClient(credentials: credentials).transitions(for: issue.key)
        transitionsCache[issue.key] = (issue.status, transitions)
        return transitions
    }

    /// What a context menu can show without waiting. A right-click has to be
    /// instant on macOS, so the menu reads this and the hover fills it in.
    func cachedTransitions(for issue: JiraIssue) -> [JiraTransition]? {
        guard let cached = transitionsCache[issue.key], cached.status == issue.status else { return nil }

        return cached.transitions
    }

    /// Warms `cachedTransitions` for a card the pointer is resting on. A failure
    /// is not worth reporting: nobody asked for anything yet.
    func prefetchTransitions(for issue: JiraIssue) async {
        _ = try? await transitions(for: issue)
    }

    /// Moves the issue, and moves the card to match.
    @discardableResult
    func move(_ issue: JiraIssue, to transition: JiraTransition) async -> Bool {
        await write(issue, confirmation: "\(issue.key) moved to \(transition.toStatus).") { client in
            try await client.transition(key: issue.key, to: transition.id)
        } apply: { moved in
            var moved = moved
            moved.status = transition.toStatus
            moved.statusCategory = transition.toStatusCategory
            return moved
        }
    }

    /// Assigns the issue; a nil accountID unassigns it.
    @discardableResult
    func assign(_ issue: JiraIssue, to accountID: String?, displayName: String?) async -> Bool {
        let confirmation = accountID == nil
            ? "\(issue.key) unassigned."
            : "\(issue.key) assigned to \(displayName ?? "you")."

        return await write(issue, confirmation: confirmation) { client in
            try await client.assign(key: issue.key, accountID: accountID)
        } apply: { assigned in
            var assigned = assigned
            assigned.assigneeAccountID = accountID
            assigned.assigneeName = accountID == nil ? nil : displayName
            return assigned
        }
    }

    /// Assigns the issue to whoever the credentials belong to.
    @discardableResult
    func assignToMe(_ issue: JiraIssue) async -> Bool {
        do {
            let me = try await myself()
            return await assign(issue, to: me.accountID, displayName: me.displayName)
        } catch {
            report(issue.key, error.localizedDescription, failed: true)
            return false
        }
    }

    /// The Jira half of starting work: assign it to yourself, then move it into
    /// progress. The branch is the window's job, and it goes first.
    func startWork(on issue: JiraIssue) async -> JiraStartWorkOutcome {
        let latest = boardIssue(for: issue.key) ?? issue

        let me: (accountID: String, displayName: String)
        let available: [JiraTransition]
        do {
            me = try await myself()
            available = try await transitions(for: latest)
        } catch {
            report(issue.key, error.localizedDescription, failed: true)
            return .failed
        }

        if latest.assigneeAccountID != me.accountID,
           await assign(latest, to: me.accountID, displayName: me.displayName) == false {
            return .failed
        }

        let current = boardIssue(for: issue.key) ?? latest

        switch JiraWorkflow.startWork(from: available, currentStatusCategory: current.statusCategory) {
        case .alreadyInProgress:
            return .alreadyInProgress
        case .noCandidate:
            return .noCandidate
        case .move(let transition):
            return await move(current, to: transition) ? .moved(to: transition.toStatus) : .failed
        }
    }

    func clearActionMessage() {
        actionMessage = nil
        actionFailed = false
        actionIssueKey = nil
    }

    // MARK: - One write

    /// The busy flag, the error handling and the optimistic board update every
    /// write needs.
    private func write(_ issue: JiraIssue,
                       confirmation: String,
                       perform: (JiraClient) async throws -> Void,
                       apply: (JiraIssue) -> JiraIssue) async -> Bool {
        guard let credentials = JiraCredentialsStore.current else {
            report(issue.key, JiraCredentialsError.missing.localizedDescription, failed: true)
            return false
        }

        // A second click on a card already being written is not a queue.
        guard busyIssues.insert(issue.key).inserted else { return false }
        defer { busyIssues.remove(issue.key) }

        // Not a guard on the write — once sent, Jira has done it — but on
        // publishing the local patch: a search that lands meanwhile is the newer
        // truth, and this update must not be laid back over it.
        let token = searchToken

        do {
            try await perform(JiraClient(credentials: credentials))

            transitionsCache[issue.key] = nil
            if searchToken == token { replace(issue.key, with: apply) }

            report(issue.key, confirmation, failed: false)
            return true
        } catch {
            report(issue.key, error.localizedDescription, failed: true)
            return false
        }
    }

    /// Corrects the board in place rather than searching again. Jira's search
    /// index runs seconds behind a write, so a refetch here would hand back the
    /// status the card just left and bounce it home.
    ///
    /// The columns come from the issues present, so the last card leaving a
    /// status takes its column with it, and a card arriving at a status nobody
    /// held opens a new one. Both settle on the next refresh.
    private func replace(_ key: String, with apply: (JiraIssue) -> JiraIssue) {
        var issues = groups.flatMap(\.issues)
        guard let index = issues.firstIndex(where: { $0.key == key }) else { return }

        issues[index] = apply(issues[index])
        groups = JiraIssueGrouping.byStatus(issues)
    }

    private func report(_ issueKey: String, _ message: String, failed: Bool) {
        actionIssueKey = issueKey
        actionFailed = failed
        actionMessage = message
    }

    /// The branch this issue suggests. A starting point, always editable.
    func suggestedBranchName(for issue: JiraIssue) -> String {
        JiraBranchName.suggest(for: issue)
    }
}
