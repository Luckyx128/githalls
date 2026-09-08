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

    @Environment(\.openURL) private var openURL

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
    }

    // MARK: - The issue

    private var issueBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(detail.key)
                    .font(.title3)
                    .fontDesign(.monospaced)
                    .bold()

                statusBadge

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
                metaRow("Assignee", detail.assigneeName ?? "Unassigned")
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
                .disabled(
                    branchName.trimmingCharacters(in: .whitespaces).isEmpty
                    || repositoryViewModel.repositoryURL == nil
                    || repositoryViewModel.isSwitchingBranch
                )
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
        }
    }
}
