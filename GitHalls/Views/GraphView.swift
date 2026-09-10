//
//  GraphView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import SwiftUI

/// The whole repository at once: every branch, where it forked, and where it
/// came back.
///
/// Selecting a commit expands it in place rather than filling a side pane. The
/// graph is the widest thing in the window and the diff is the tallest, so
/// splitting the two squeezed both; opening the detail under its own row keeps
/// the commit you clicked next to what it changed.
struct GraphView: View {
    @Bindable var viewModel: RepositoryViewModel

    @State private var sheet: GraphSheet?

    private var gutterWidth: CGFloat {
        GraphMetrics.gutterWidth(laneCount: viewModel.graphLaneCount)
    }

    private var headHash: String? {
        viewModel.graphRows.first { row in
            row.commit.refs.contains { $0.kind == .head }
        }?.commit.hash
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .confirmationDialog(
                "Delete \"\(viewModel.pendingRemoteBranchDeletion ?? "")\" on the remote?",
                isPresented: Binding(
                    get: { viewModel.pendingRemoteBranchDeletion != nil },
                    set: { if !$0 { viewModel.cancelRemoteBranchDeletion() } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete on Remote", role: .destructive) {
                    Task { await viewModel.confirmRemoteBranchDeletion() }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelRemoteBranchDeletion()
                }
            } message: {
                Text("This cannot be undone, and it affects everyone else working on that branch.")
            }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if viewModel.repositoryURL == nil {
                ContentUnavailableView("No Repository", systemImage: "point.3.filled.connected.trianglepath.dotted")
            } else if viewModel.graphRows.isEmpty {
                if viewModel.isLoadingGraph {
                    ProgressView().controlSize(.small)
                } else {
                    ContentUnavailableView(
                        "No Commits in the Last Two Months",
                        systemImage: "point.3.filled.connected.trianglepath.dotted"
                    )
                }
            } else {
                list
            }
        }
        // The placeholders have small intrinsic heights; without this the pane
        // shrinks to fit them instead of holding the window's full height.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List(selection: $viewModel.selectedCommitID) {
            ForEach(viewModel.graphRows) { row in
                GraphRowView(
                    row: row,
                    laneCount: viewModel.graphLaneCount,
                    gutterWidth: gutterWidth,
                    isHead: row.commit.hash == headHash
                )
                .tag(row.commit.hash)
                // The lanes only join up if every row is exactly the same height
                // with nothing between them. An inset or a separator turns the
                // graph into dashes.
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .contextMenu {
                    GraphCommitContextMenu(viewModel: viewModel, commit: row.commit) { sheet = $0 }
                }

                if viewModel.selectedCommitID == row.commit.hash {
                    CommitInlineDetailView(
                        viewModel: viewModel,
                        row: row,
                        laneCount: viewModel.graphLaneCount,
                        gutterWidth: gutterWidth
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    // It is a disclosure, not another commit — clicking it must
                    // not move the selection off the row that opened it.
                    .selectionDisabled()
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, GraphMetrics.rowHeight)
    }
}
