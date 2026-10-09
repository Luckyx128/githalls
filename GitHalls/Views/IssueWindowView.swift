//
//  IssueWindowView.swift
//  GitHalls
//

import SwiftUI

/// One issue in a window of its own, like Settings: the card on the board is a
/// summary, and reading a description or naming a branch wants room and a place
/// that stays open while the board is used.
///
/// This is the only place the two view models are held together. Jira knows
/// nothing about repositories and the repository knows nothing about issues —
/// the join lives here, in the screen that actually needs both.
struct IssueWindowView: View {
    let issue: JiraIssue
    @Bindable var jiraViewModel: JiraViewModel
    @Bindable var repositoryViewModel: RepositoryViewModel
    @Bindable var clockifyViewModel: ClockifyViewModel

    /// Starts as the card the board handed over, and is replaced by the full
    /// issue once Jira answers.
    @State private var detail: JiraIssue
    @State private var isLoadingDetail = false
    @State private var detailError: String?
    @State private var branchName = ""
    @State private var isLinking = false

    /// The moves this issue can make, fetched once per status the window shows.
    @State private var transitions: [JiraTransition] = []

    /// The outcome of the last action taken here, and whether it went wrong.
    @State private var actionResult: (message: String, failed: Bool)?

    /// The priorities the site offers, for the menu. Fetched once.
    @State private var priorities: [JiraFieldOption] = []

    @Environment(\.openURL) private var openURL

    private var isBusy: Bool { jiraViewModel.busyIssues.contains(detail.key) }

    init(issue: JiraIssue, jiraViewModel: JiraViewModel, repositoryViewModel: RepositoryViewModel,
         clockifyViewModel: ClockifyViewModel) {
        self.issue = issue
        self.jiraViewModel = jiraViewModel
        self.repositoryViewModel = repositoryViewModel
        self.clockifyViewModel = clockifyViewModel
        _detail = State(initialValue: issue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                issueBox
                descriptionBox
                IssueRelationsView(issue: $detail, jiraViewModel: jiraViewModel)
                IssueAttachmentsView(issueKey: detail.key, jiraViewModel: jiraViewModel)
                IssueWorklogView(issueKey: detail.key, jiraViewModel: jiraViewModel)
                IssueClockifyView(issueKey: detail.key, summary: detail.summary, clockify: clockifyViewModel)
                IssueCommentsView(issueKey: detail.key, jiraViewModel: jiraViewModel)
                branchBox
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 520)
        .navigationTitle(detail.key)
        .task(id: issue.key) {
            branchName = jiraViewModel.suggestedBranchName(for: issue)
            await loadDetail()
        }
        // Re-asked whenever the issue moves: which moves are available is a
        // function of where it stands.
        .task {
            priorities = (try? await JiraAuthoringFactory.make().priorities()) ?? []
        }
        .task(id: detail.status) {
            transitions = (try? await jiraViewModel.transitions(for: detail)) ?? []
        }
        .onChange(of: jiraViewModel.boardIssue(for: issue.key)) { _, fresh in
            guard let fresh else { return }

            // Only the fields a write can move. The board's copy comes from the
            // search, which never asks for a description, and this window has
            // already paid for one.
            detail.status = fresh.status
            detail.statusCategory = fresh.statusCategory
            detail.assigneeName = fresh.assigneeName
            detail.assigneeAccountID = fresh.assigneeAccountID
        }
    }

    // MARK: - The issue

    private var issueBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(detail.key)
                    .font(.title3)
                    .fontDesign(.monospaced)
                    .bold()

                statusMenu

                Spacer()

                Button("Open in Jira") {
                    if let url = jiraViewModel.browseURL(for: detail) { openURL(url) }
                }
            }

            InlineEditText(text: detail.summary, placeholder: "Summary") { new in
                let title = new.trimmingCharacters(in: .whitespacesAndNewlines)
                guard await jiraViewModel.setSummary(detail, title) else { return false }
                detail.summary = title
                return true
            } display: {
                Text(detail.summary)
                    .font(.title3)
                    .textSelection(.enabled)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                metaRow("Type", detail.type)
                priorityRow
                assigneeRow
                metaRow("Reporter", detail.reporterName ?? "—")
                metaRow("Created", formatted(detail.created))
                metaRow("Updated", formatted(detail.updated))
            }
            .font(.callout)

            InlineEditText(text: detail.labels.joined(separator: " "), placeholder: "labels, space or comma separated") { new in
                let labels = JiraCreateIssueViewModel.labels(from: new)
                guard await jiraViewModel.setLabels(detail, labels) else { return false }
                detail.labels = labels
                return true
            } display: {
                if detail.labels.isEmpty {
                    Text("No labels").font(.callout).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(detail.labels, id: \.self) { label in
                            Text(label)
                                .font(.callout)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    /// Still the badge, and now the way to move the issue: the status is the
    /// thing you want to change while looking at it.
    private var statusMenu: some View {
        Menu {
            if transitions.isEmpty {
                Button("No moves available") {}.disabled(true)
            } else {
                ForEach(transitions) { transition in
                    Button(JiraWorkflow.label(for: transition, among: transitions)
                           + (transition.hasScreen ? "…" : "")) {
                        Task { await jiraViewModel.move(detail, to: transition) }
                    }
                }
            }
        } label: {
            statusBadge
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isBusy)
        .help("Move this issue")
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(detail.status)
                .font(.callout)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }

    private var statusColor: Color {
        switch detail.statusCategory {
        case "done": .green
        case "indeterminate": .blue
        default: .secondary
        }
    }

    private var assigneeRow: some View {
        GridRow {
            Text("Assignee")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(detail.assigneeName ?? "Unassigned")

                // Hidden once we know it is already yours — which we may not
                // know at first paint: the account id arrives with the board's
                // first search, after this window may already be open.
                if jiraViewModel.myAccountID == nil || detail.assigneeAccountID != jiraViewModel.myAccountID {
                    Button("Assign to me") {
                        Task { await jiraViewModel.assignToMe(detail) }
                    }
                    .buttonStyle(.link)
                    .disabled(isBusy)
                }
            }
        }
    }

    private var priorityRow: some View {
        GridRow {
            Text("Priority")
                .foregroundStyle(.secondary)

            Menu(detail.priority ?? "—") {
                ForEach(priorities) { priority in
                    Button(priority.label) {
                        Task {
                            if await jiraViewModel.setPriority(detail, priority) {
                                detail.priority = priority.label
                            }
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isBusy || priorities.isEmpty)
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date, date != .distantPast else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Description

    private var descriptionBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Description")
                    .font(.headline)
                if isLoadingDetail {
                    ProgressView().controlSize(.small)
                }
            }

            if let detailError {
                Text(detailError)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if let description = detail.description {
                // Empty means Jira has none, which is worth stating rather than
                // leaving a blank box.
                InlineEditText(text: description, multiline: true) { new in
                    guard await jiraViewModel.setDescription(detail, new) else { return false }
                    detail.description = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    return true
                } display: {
                    Text(description.isEmpty ? "This issue has no description." : description)
                        .font(.callout)
                        .foregroundStyle(description.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func loadDetail() async {
        isLoadingDetail = true
        detailError = nil

        do {
            detail = try await jiraViewModel.fetchIssue(key: issue.key)
        } catch {
            detailError = error.localizedDescription
        }

        isLoadingDetail = false
    }

    // MARK: - Branch

    private var branchBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Create branch from this issue")
                .font(.headline)

            HStack {
                TextField("Branch name", text: $branchName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    // Suggested, never imposed: the name is editable before
                    // anything is created.
                    branchName = jiraViewModel.suggestedBranchName(for: issue)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Back to the suggested name")

                Button("Create Branch") {
                    Task { await repositoryViewModel.createBranch(named: branchName) }
                }
                .disabled(!canCreateBranch)

                // Three things in one click, so the help says all three.
                Button("Start Work") {
                    Task { await startWork() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreateBranch || isBusy)
                .help("Creates the branch, assigns the issue to you, and moves it to the in-progress status.")
            }

            if let repoURL = repositoryViewModel.repositoryURL {
                Text("Will be created in \(repoURL.lastPathComponent), from the branch checked out there now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open a repository first — a branch needs somewhere to be created.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Link Pull Request") { Task { await linkPullRequest() } }
                    .disabled(repositoryViewModel.repositoryURL == nil || isBusy || isLinking)
                    .help("Comments the open pull request of the checked-out branch on this issue.")
                if isLinking { ProgressView().controlSize(.small) }
                Text("Posts the open PR of the current branch as a comment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let actionResult {
                Label(actionResult.message,
                      systemImage: actionResult.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(actionResult.failed ? Color.red : Color.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func linkPullRequest() async {
        guard !isLinking else { return }
        isLinking = true
        defer { isLinking = false }
        actionResult = nil

        guard let pullRequest = await repositoryViewModel.openPullRequest() else {
            actionResult = ("No open pull request for the branch checked out. Create one first.", true)
            return
        }

        // The thread may not have been opened yet; the check needs it.
        try? await jiraViewModel.loadComments(for: detail.key)
        if JiraPullRequestLink.isLinked(pullRequest, in: jiraViewModel.commentsByIssue[detail.key] ?? []) {
            actionResult = ("PR #\(pullRequest.number) is already linked to \(detail.key).", false)
            return
        }

        if await jiraViewModel.addComment(to: detail.key, text: JiraPullRequestLink.commentText(for: pullRequest)) {
            actionResult = ("Linked PR #\(pullRequest.number) to \(detail.key).", false)
        } else {
            actionResult = (jiraViewModel.actionMessage ?? "Jira refused the comment.", true)
        }
    }

    private var canCreateBranch: Bool {
        !branchName.trimmingCharacters(in: .whitespaces).isEmpty
        && repositoryViewModel.repositoryURL != nil
        && !repositoryViewModel.isSwitchingBranch
    }

    /// Branch, then assign, then move — in that order on purpose. The local step
    /// is the one most likely to fail (no repository open, a name already
    /// taken), and claiming an issue for work that then has nowhere to happen is
    /// the worse half to get wrong.
    private func startWork() async {
        actionResult = nil

        await repositoryViewModel.createBranch(named: branchName.trimmingCharacters(in: .whitespaces))
        if let error = repositoryViewModel.errorMessage {
            actionResult = (error, true)
            return
        }

        // A partial success is worth stating plainly, not dressing as an error.
        switch await jiraViewModel.startWork(on: detail) {
        case .moved(let status):
            actionResult = ("Branch created, assigned to you, moved to \(status).", false)
        case .alreadyInProgress:
            actionResult = ("Branch created and assigned to you. It was already in progress.", false)
        case .noCandidate:
            actionResult = ("Branch created and assigned to you. This workflow has no in-progress move — change the status in Jira.", false)
        case .failed:
            actionResult = (jiraViewModel.actionMessage ?? "Jira refused the change.", true)
        }
    }
}
