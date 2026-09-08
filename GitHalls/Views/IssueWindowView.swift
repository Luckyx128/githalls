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

    /// Starts as the card the board handed over, and is replaced by the full
    /// issue once Jira answers.
    @State private var detail: JiraIssue
    @State private var isLoadingDetail = false
    @State private var detailError: String?
    @State private var branchName = ""

    /// The moves this issue can make, fetched once per status the window shows.
    @State private var transitions: [JiraTransition] = []

    /// The outcome of the last action taken here, and whether it went wrong.
    @State private var actionResult: (message: String, failed: Bool)?

    @Environment(\.openURL) private var openURL

    private var isBusy: Bool { jiraViewModel.busyIssues.contains(detail.key) }

    init(issue: JiraIssue, jiraViewModel: JiraViewModel, repositoryViewModel: RepositoryViewModel) {
        self.issue = issue
        self.jiraViewModel = jiraViewModel
        self.repositoryViewModel = repositoryViewModel
        _detail = State(initialValue: issue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                issueBox
                descriptionBox
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

            Text(detail.summary)
                .font(.title3)
                .textSelection(.enabled)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                metaRow("Type", detail.type)
                metaRow("Priority", detail.priority ?? "—")
                assigneeRow
                metaRow("Reporter", detail.reporterName ?? "—")
                metaRow("Created", formatted(detail.created))
                metaRow("Updated", formatted(detail.updated))
            }
            .font(.caption)

            if !detail.labels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(detail.labels, id: \.self) { label in
                        Text(label)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
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
                .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let description = detail.description {
                // Empty means Jira has none, which is worth stating rather than
                // leaving a blank box.
                Text(description.isEmpty ? "This issue has no description." : description)
                    .font(.callout)
                    .foregroundStyle(description.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open a repository first — a branch needs somewhere to be created.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let actionResult {
                Label(actionResult.message,
                      systemImage: actionResult.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(actionResult.failed ? Color.red : Color.secondary)
                    .padding(.top, 2)
            }
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
