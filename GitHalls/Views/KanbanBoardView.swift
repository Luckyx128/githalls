//
//  KanbanBoardView.swift
//  GitHalls
//

import SwiftUI

/// The board: one column per status, a card per issue. Clicking a card opens
/// the issue in its own window — the card is a summary, not a place to read.
struct KanbanBoardView: View {
    @Bindable var viewModel: JiraViewModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.columns.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                columns
            }
        }
        // One task, not one per trigger: two of them both fire on appear and
        // the board would ask Jira the same question twice.
        .task(id: Reload(token: viewModel.reloadToken, isConfigured: viewModel.isConfigured)) {
            guard viewModel.isConfigured else { return }
            await viewModel.refresh()
        }
    }

    /// What the board reloads for: a different query, an edited one, or an
    /// account that has just been connected.
    private struct Reload: Equatable {
        let token: UUID
        let isConfigured: Bool
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.selectedQuery.name)
                    .font(.headline)
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help(viewModel.selectedQuery.jql)

            Spacer()

            // Narrows what is already on the board; never asks Jira.
            TextField("Filter cards", text: $viewModel.filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .disabled(viewModel.issueCount == 0)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var countLabel: String {
        if viewModel.isLoading && !viewModel.hasSearched { return "Loading…" }

        return viewModel.shownCount == viewModel.issueCount
            ? "\(viewModel.issueCount) issues"
            : "\(viewModel.shownCount) of \(viewModel.issueCount) issues"
    }

    // MARK: - Columns

    private var columns: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(viewModel.columns) { column in
                    KanbanColumnView(column: column) { issue in
                        openWindow(id: "issue", value: issue)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !viewModel.isConfigured {
            ContentUnavailableView {
                Label("Jira Not Connected", systemImage: "link.badge.plus")
            } description: {
                Text("Connect a Jira account to see your board here.")
            } actions: {
                SettingsLink { Text("Open Settings") }
            }
        } else if let errorMessage = viewModel.errorMessage {
            // A rejected JQL lands here, and Jira says precisely what it disliked.
            ContentUnavailableView(
                "Jira Could Not Run This Query",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if viewModel.isLoading {
            ProgressView()
        } else {
            ContentUnavailableView(
                "No Issues",
                systemImage: "flag",
                description: Text(viewModel.hasSearched
                                  ? "No issues match this query. If your project has no active sprint, try another query."
                                  : "Run the query to see your issues.")
            )
        }
    }
}

/// One status column: a header, then its cards, scrolling on their own.
private struct KanbanColumnView: View {
    let column: JiraIssueGroup
    let onOpen: (JiraIssue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Self.color(for: column.category))
                    .frame(width: 8, height: 8)
                Text(column.status)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(column.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(column.issues) { issue in
                        KanbanCardView(issue: issue) { onOpen(issue) }
                    }

                    if column.issues.isEmpty {
                        Text("Nothing here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.gray.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Jira's three categories, in the colours the app already uses for state.
    static func color(for category: String) -> Color {
        switch category {
        case "done": .green
        case "indeterminate": .blue
        default: .secondary
        }
    }
}

/// KEY · type · priority, the title, and who has it.
private struct KanbanCardView: View {
    let issue: JiraIssue
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                Text(issue.summary)
                    .font(.callout)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let assignee = issue.assigneeName {
                    Text(assignee)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("\(issue.key) — \(issue.summary)")
    }

    /// The key first, since it is what people say out loud.
    private var metaLine: String {
        [issue.key, issue.type, issue.priority].compactMap { $0 }.joined(separator: " · ")
    }
}
