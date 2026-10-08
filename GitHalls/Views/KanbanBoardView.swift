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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var board: KanbanBoardModel
    @State private var isCreating = false

    init(viewModel: JiraViewModel) {
        self.viewModel = viewModel
        _board = State(initialValue: KanbanBoardModel(jira: viewModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let actionMessage = viewModel.actionMessage {
                actionBanner(actionMessage)
            }

            if board.allColumns.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                columns
            }
        }
        .sheet(isPresented: $isCreating) {
            CreateIssueSheet(jiraViewModel: viewModel,
                             projectKey: JiraQuickCreate.projectKey(from: viewModel.columns.flatMap(\.issues).map(\.key)))
        }
        // One task, not one per trigger: two of them both fire on appear and
        // the board would ask Jira the same question twice.
        .confirmationDialog(
            "Move \(board.choice?.issue.key ?? "")",
            isPresented: Binding(get: { board.choice != nil }, set: { if !$0 { board.choice = nil } }),
            presenting: board.choice
        ) { choice in
            ForEach(choice.options) { option in
                Button("\(option.name) → \(option.toStatus)") { board.choose(option) }
            }
        } message: { choice in
            Text("Several moves lead to \(choice.options[0].toStatus). Which one?")
        }
        .task(id: Reload(token: viewModel.reloadToken, isConfigured: viewModel.isConfigured)) {
            guard viewModel.isConfigured else { return }
            await viewModel.refresh()
            board.settle()
            await board.prepareBoards()
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .help(viewModel.selectedQuery.jql)

            Spacer()

            // Narrows what is already on the board; never asks Jira.
            TextField("Filter cards", text: $viewModel.filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .disabled(viewModel.issueCount == 0)

            columnsMenu

            Button {
                isCreating = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Create issue")
            .disabled(!viewModel.isConfigured)

            Button {
                Task {
                    await viewModel.refresh()
                    board.settle()
                }
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

    /// Which columns the board shows; hidden ones come back from here.
    private var columnsMenu: some View {
        Menu {
            if !viewModel.boards.isEmpty {
                Picker("Columns from", selection: Binding(
                    get: { viewModel.selectedBoard?.id },
                    set: { id in Task { await board.chooseBoard(viewModel.boards.first { $0.id == id }) } }
                )) {
                    Text("Statuses on the board").tag(Int?.none)
                    ForEach(viewModel.boards) { Text($0.name).tag(Int?.some($0.id)) }
                }
                .pickerStyle(.menu)

                Divider()
            }

            ForEach(board.allColumns) { column in
                Toggle(column.status, isOn: Binding(
                    get: { !board.layout.hidden.contains(column.status) },
                    set: { _ in board.toggleHidden(column.status) }
                ))
            }
        } label: {
            Image(systemName: "rectangle.split.3x1")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Show or hide columns")
    }

    private var countLabel: String {
        if viewModel.isLoading && !viewModel.hasSearched { return "Loading…" }

        return viewModel.shownCount == viewModel.issueCount
            ? "\(viewModel.issueCount) issues"
            : "\(viewModel.shownCount) of \(viewModel.issueCount) issues"
    }

    /// What the last move or assign did. The empty state below can't say it:
    /// that one is only on screen when the board has no columns, which is
    /// exactly when a write cannot have happened.
    private func actionBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.actionFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(viewModel.actionFailed ? .red : .green)

            Text(message)
                .font(.callout)
                .lineLimit(2)

            Spacer()

            Button {
                viewModel.clearActionMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Columns

    private var columns: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(board.visibleColumns) { column in
                    KanbanColumnView(
                        column: column,
                        viewModel: viewModel,
                        board: board,
                        isCollapsed: board.layout.collapsed.contains(column.status)
                    ) { issue in
                        openWindow(id: "issue", value: issue)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(KanbanMotion(reduced: reduceMotion).spring, value: board.visibleColumns.map(\.status))
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
