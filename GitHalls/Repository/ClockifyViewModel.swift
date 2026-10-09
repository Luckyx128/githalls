//
//  ClockifyViewModel.swift
//  GitHalls
//

import Foundation
import Observation

/// Clockify state, one for the whole app: Clockify runs a single timer per
/// user, so every issue window has to agree on which one is running.
///
/// It does not touch Jira. Time logged here goes to Clockify only, named after
/// the issue; the Jira work log is a separate thing the user fills or not.
@Observable
@MainActor
final class ClockifyViewModel {
    private(set) var user: ClockifyUser?
    private(set) var workspaces: [ClockifyWorkspace] = []
    private(set) var workspaceID: String?
    private(set) var projects: [ClockifyProject] = []
    private(set) var tags: [ClockifyTag] = []

    /// The user's running timer, wherever it was started — the web app, the
    /// browser extension, another window.
    private(set) var running: ClockifyTimeEntry?

    var isLoading = false
    var isWriting = false
    var errorMessage: String?

    /// Where the client comes from; tests hand in one wired to a mock session.
    var makeClient: () -> ClockifyClient? = {
        ClockifyCredentialsStore.apiKey.map { ClockifyClient(apiKey: $0) }
    }

    var isConfigured: Bool { makeClient() != nil }

    /// Forgets everything fetched, so the next `load` starts from the new key.
    func reset() {
        user = nil
        workspaces = []
        workspaceID = nil
        projects = []
        tags = []
        running = nil
        errorMessage = nil
    }

    /// Who the key belongs to and what they can log against. Cheap to call
    /// again: it only asks once per key.
    func load() async {
        guard user == nil, !isLoading else { return }
        guard let client = makeClient() else { errorMessage = ClockifyError.notConnected.errorDescription; return }

        isLoading = true
        defer { isLoading = false }

        do {
            let me = try await client.user()
            let spaces = try await client.workspaces()
            user = me
            workspaces = spaces

            let remembered = ClockifyPreferences.workspaceID.flatMap { id in spaces.contains { $0.id == id } ? id : nil }
            workspaceID = remembered ?? me.activeWorkspaceID ?? spaces.first?.id
            try await loadWorkspace(client)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectWorkspace(_ id: String) async {
        guard id != workspaceID, let client = makeClient() else { return }
        workspaceID = id
        ClockifyPreferences.workspaceID = id
        projects = []
        tags = []

        isLoading = true
        defer { isLoading = false }
        do {
            try await loadWorkspace(client)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadWorkspace(_ client: ClockifyClient) async throws {
        guard let workspaceID, let user else { return }
        async let projects = client.projects(workspaceID: workspaceID)
        async let tags = client.tags(workspaceID: workspaceID)
        async let running = client.runningEntry(workspaceID: workspaceID, userID: user.id)
        (self.projects, self.tags, self.running) = try await (projects, tags, running)
    }

    /// Asks again whether a timer runs; another app may have started or stopped it.
    func refreshRunning() async {
        guard let client = makeClient(), let workspaceID, let user else { return }
        // A failed ask keeps what is on screen; only an answer changes it.
        do { running = try await client.runningEntry(workspaceID: workspaceID, userID: user.id) } catch {}
    }

    func tasks(projectID: String, matching name: String? = nil) async throws -> [ClockifyTask] {
        guard let client = makeClient(), let workspaceID else { throw ClockifyError.notConnected }
        return try await client.tasks(workspaceID: workspaceID, projectID: projectID, name: name)
    }

    // MARK: - Writes

    /// Logs a finished stretch of time. True when Clockify took it.
    func addTime(_ entry: ClockifyNewEntry) async -> Bool {
        await write { client, workspaceID, _ in
            _ = try await client.addEntry(workspaceID: workspaceID, entry)
        }
    }

    /// Starts a timer for this entry, stopping whatever runs first: Clockify
    /// keeps one timer per user, and stopping it ourselves keeps its end honest.
    func startTimer(_ entry: ClockifyNewEntry) async -> Bool {
        await write { client, workspaceID, user in
            if self.running != nil {
                _ = try await client.stopTimer(workspaceID: workspaceID, userID: user.id)
                self.running = nil
            }
            var timer = entry
            timer.end = nil
            self.running = try await client.addEntry(workspaceID: workspaceID, timer)
        }
    }

    func stopTimer() async -> Bool {
        await write { client, workspaceID, user in
            _ = try await client.stopTimer(workspaceID: workspaceID, userID: user.id)
            self.running = nil
        }
    }

    private func write(_ body: (ClockifyClient, String, ClockifyUser) async throws -> Void) async -> Bool {
        guard !isWriting else { return false }
        guard let client = makeClient(), let workspaceID, let user else {
            errorMessage = ClockifyError.notConnected.errorDescription
            return false
        }

        isWriting = true
        defer { isWriting = false }
        do {
            try await body(client, workspaceID, user)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// What a timer for this issue starts with when nobody fills the form:
    /// "[KEY]: summary", the project and tags this Jira project used last, and
    /// the task named after the key.
    func draft(key: String, summary: String) async -> ClockifyNewEntry {
        var entry = ClockifyNewEntry(description: Self.description(key: key, summary: summary), start: .now)
        guard let workspaceID else { return entry }

        let project = JiraIssueKey.project(of: key)
        if let projectID = ClockifyPreferences.projectID(forJiraProject: project, workspaceID: workspaceID),
           projects.contains(where: { $0.id == projectID }) {
            entry.projectID = projectID
            let found = (try? await tasks(projectID: projectID, matching: key)) ?? []
            entry.taskID = Self.task(for: key, in: found)?.id
        }
        let known = Set(tags.map(\.id))
        entry.tagIDs = ClockifyPreferences.tagIDs(forJiraProject: project, workspaceID: workspaceID).filter(known.contains)
        return entry
    }

    // MARK: - Helpers for an issue

    /// "[SWEB-6851]: (Front) Melhoria pdf", the way the Clockify extension names it.
    nonisolated static func description(key: String, summary: String) -> String {
        "[\(key)]: \(summary)"
    }

    /// The task the Jira integration made for this issue: its name is the key,
    /// or starts with it.
    nonisolated static func task(for key: String, in tasks: [ClockifyTask]) -> ClockifyTask? {
        let upper = key.uppercased()
        return tasks.first { $0.name.uppercased() == upper }
            ?? tasks.first { $0.name.uppercased().hasPrefix(upper) }
    }

    /// "SWEB" from "SWEB-6851".
    nonisolated static func jiraProjectKey(of issueKey: String) -> String {
        String(issueKey.split(separator: "-").first ?? Substring(issueKey))
    }

    /// "01:05:09", the way a timer reads.
    nonisolated static func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
