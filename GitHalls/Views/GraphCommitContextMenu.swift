//
//  GraphCommitContextMenu.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import SwiftUI

/// The sheets the graph's context menu can raise. Presented by `GraphView`, not
/// by the row: rows are recycled as the list scrolls, and a sheet owned by one
/// would vanish with it.
enum GraphSheet: Identifiable {
    case createBranch(GraphCommit)
    case rename(String)
    case setUpstream(String)

    var id: String {
        switch self {
        case .createBranch(let commit): "createBranch:\(commit.hash)"
        case .rename(let branch): "rename:\(branch)"
        case .setUpstream(let branch): "setUpstream:\(branch)"
        }
    }
}

/// Everything you can do from a commit in the graph.
///
/// Every action closes over `commit`, never over the view model's selection: on
/// macOS a right-click on an unselected row still opens that row's menu, so
/// reading the selection here would silently act on a different commit.
struct GraphCommitContextMenu: View {
    @Bindable var viewModel: RepositoryViewModel
    let commit: GraphCommit
    let presentSheet: (GraphSheet) -> Void

    private var isHead: Bool {
        commit.refs.contains { $0.kind == .head }
    }

    var body: some View {
        Button("Copy Commit Hash") {
            QuickActions.copyToClipboard(commit.hash)
        }
        Button("Copy Short Hash") {
            QuickActions.copyToClipboard(commit.shortHash)
        }
        Button("Copy Commit Message") {
            Task { await viewModel.copyCommitMessage(commit.hash) }
        }

        Divider()

        Button("Checkout Commit (Detached)") {
            Task { await viewModel.checkoutCommit(commit.hash) }
        }
        .disabled(isHead || viewModel.isMutatingBranch)

        Button("Create Branch from Here…") {
            presentSheet(.createBranch(commit))
        }

        // One submenu per ref: a commit carrying five branches would otherwise
        // produce thirty loose items with no way to tell which belongs to which.
        ForEach(commit.refs.filter { $0.kind == .localBranch || $0.kind == .remoteBranch }) { ref in
            Divider()
            switch ref.kind {
            case .localBranch: localBranchMenu(ref.name)
            case .remoteBranch: remoteBranchMenu(ref.name)
            default: EmptyView()
            }
        }
    }

    @ViewBuilder
    private func localBranchMenu(_ name: String) -> some View {
        let isCurrent = viewModel.currentBranch == name

        Menu(name) {
            Button("Checkout") {
                Task { await viewModel.switchBranch(to: name) }
            }
            .disabled(isCurrent || viewModel.isSwitchingBranch)

            Button("Rename…") { presentSheet(.rename(name)) }

            Button("Push") {
                Task { await viewModel.pushBranch(name, setUpstream: true) }
            }
            .disabled(viewModel.isMutatingBranch)

            Button("Set Upstream…") { presentSheet(.setUpstream(name)) }

            // `git pull` only ever updates the checked-out branch. For any other
            // branch the honest offer is the fast-forward refspec, under a name
            // that says what it actually does.
            if isCurrent {
                Button("Pull") {
                    Task { await viewModel.pull() }
                }
                .disabled(viewModel.isPulling)
            } else {
                Button("Fetch into \"\(name)\"") {
                    Task { await viewModel.fastForwardBranch(name) }
                }
                .disabled(viewModel.isMutatingBranch)
            }

            Divider()

            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteLocalBranch(named: name) }
            }
            .disabled(isCurrent || viewModel.isMutatingBranch)
        }
    }

    @ViewBuilder
    private func remoteBranchMenu(_ name: String) -> some View {
        Menu(name) {
            Button("Checkout as Local Branch") {
                Task { await viewModel.switchBranch(to: Branch.remoteShortName(from: name)) }
            }
            .disabled(viewModel.isSwitchingBranch)

            Divider()

            Button("Delete on Remote…", role: .destructive) {
                viewModel.requestRemoteBranchDeletion(name)
            }
            .disabled(viewModel.isMutatingBranch)
        }
    }
}
