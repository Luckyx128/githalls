//
//  HistorySidebarView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 29/08/26.
//

import Foundation
import SwiftUI

/// The commit list, drawn as a graph: a lane gutter on the left of every row,
/// the commit's summary and byline to its right. Selecting a row shows it in
/// the detail pane.
struct HistorySidebarView: View {
    @Bindable var viewModel: RepositoryViewModel

    @State private var sheet: GraphSheet?

    /// The sidebar is ~280pt wide; more columns than this would leave no room
    /// for the text.
    private static let maxLanes = 5

    private var gutterWidth: CGFloat {
        GraphMetrics.gutterWidth(laneCount: viewModel.graphLaneCount, maxLanes: Self.maxLanes)
    }

    private var headHash: String? {
        viewModel.graphRows.first { row in
            row.commit.refs.contains { $0.kind == .head }
        }?.commit.hash
    }

    var body: some View {
        VStack(spacing: 0) {
            scopePicker
            content
        }
        .task(id: viewModel.repositoryURL) {
            await viewModel.loadGraph()
        }
        .onChange(of: viewModel.selectedCommitID) {
            Task { await viewModel.loadCommitDetail() }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .createBranch(let commit):
                CreateBranchFromCommitSheetView(viewModel: viewModel, commit: commit)
            case .rename(let branch):
                RenameBranchSheetView(viewModel: viewModel, branch: branch)
            case .setUpstream(let branch):
                SetUpstreamSheetView(viewModel: viewModel, branch: branch)
            }
        }
        .alert(
            viewModel.pendingForceDeleteBranch != nil ? "Branch Not Fully Merged" : "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            // git refused to delete the branch rather than strand the commits
            // only it holds. Still doable — but not without saying so.
            if let branch = viewModel.pendingForceDeleteBranch {
                Button("Delete Anyway", role: .destructive) {
                    Task { await viewModel.deleteLocalBranch(named: branch, force: true) }
                }
                Button("Cancel", role: .cancel) { viewModel.dismissError() }
            } else {
                Button("OK") { viewModel.dismissError() }
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // `presenting:` hands the branch to the button. The dialog flips its
        // binding to false *before* running the action, which clears the
        // pending name — reading it back from the view model would find nil.
        .confirmationDialog(
            "Delete \"\(viewModel.pendingRemoteBranchDeletion ?? "")\" on the remote?",
            isPresented: Binding(
                get: { viewModel.pendingRemoteBranchDeletion != nil },
                set: { if !$0 { viewModel.cancelRemoteBranchDeletion() } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.pendingRemoteBranchDeletion
        ) { remoteBranch in
            Button("Delete on Remote", role: .destructive) {
                Task { await viewModel.deleteRemoteBranch(remoteBranch) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelRemoteBranchDeletion()
            }
        } message: { _ in
            Text("This cannot be undone, and it affects everyone else working on that branch.")
        }
    }

    private var scopePicker: some View {
        Picker("Scope", selection: Binding(
            get: { viewModel.graphShowsAllBranches },
            set: { newValue in
                viewModel.graphShowsAllBranches = newValue
                Task { await viewModel.loadGraph() }
            }
        )) {
            Text("All branches").tag(true)
            Text("Current branch").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .disabled(viewModel.repositoryURL == nil)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if viewModel.repositoryURL == nil {
                ContentUnavailableView("No Repository", systemImage: "clock")
            } else if viewModel.graphRows.isEmpty {
                if viewModel.isLoadingGraph {
                    ProgressView().controlSize(.small)
                } else {
                    ContentUnavailableView("No Recent Commits", systemImage: "clock")
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List(selection: $viewModel.selectedCommitID) {
            ForEach(viewModel.graphRows) { row in
                CommitRow(
                    row: row,
                    laneCount: viewModel.graphLaneCount,
                    maxLanes: Self.maxLanes,
                    gutterWidth: gutterWidth,
                    isHead: row.commit.hash == headHash,
                    isUnpushed: viewModel.unpushedCommitHashes.contains(row.commit.hash)
                )
                .tag(row.commit.hash)
                // The lanes only join up if every row is exactly the same height
                // with nothing between them.
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .contextMenu {
                    GraphCommitContextMenu(viewModel: viewModel, commit: row.commit) { sheet = $0 }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, CommitRow.height)
    }
}

struct CommitRow: View {
    static let height: CGFloat = 44

    let row: GraphRow
    let laneCount: Int
    let maxLanes: Int
    let gutterWidth: CGFloat
    let isHead: Bool
    let isUnpushed: Bool

    private var commit: GraphCommit { row.commit }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Only the refs worth the width: HEAD and local branches. Remotes and tags
    /// stay in the context menu and the tooltip.
    private var chipRefs: [GitRef] {
        commit.refs.filter { $0.kind == .head || $0.kind == .localBranch }
    }

    var body: some View {
        HStack(spacing: 6) {
            GraphLaneCanvas(row: row, laneCount: laneCount, isHead: isHead, maxLanes: maxLanes)
                .frame(width: gutterWidth, height: Self.height)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if !chipRefs.isEmpty {
                        GraphRefChips(refs: chipRefs, visibleLimit: 1)
                            .layoutPriority(1)
                    }
                    Text(commit.summary)
                        .font(.rowPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    Text(commit.compactAuthorsLabel)
                        .lineLimit(1)
                        .help(commit.coAuthors.isEmpty ? "" : commit.allAuthorsLabel)
                    Text("·")
                    Text(Self.relativeFormatter.localizedString(for: commit.date, relativeTo: Date()))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    if isUnpushed {
                        Image(systemName: "arrow.up.circle")
                            .foregroundStyle(Color.accentColor)
                            .help("Not pushed yet")
                    }
                    Text(commit.shortHash)
                        .font(.rowMono)
                }
                .font(.rowSecondary)
                .foregroundStyle(.secondary)
            }
            .padding(.trailing, 8)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
    }
}
