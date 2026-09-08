//
//  SyncButton.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 30/08/26.
//

import Foundation
import SwiftUI

struct SyncButton: View {
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        Button {
            performAction()
        } label: {
            HStack(spacing: 4) {
                Group {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: iconName)
                    }
                }
                .frame(width: 16, height: 16)

                Text(title)
            }
            .frame(minWidth: 96, alignment: .leading)
        }
        .disabled(isLoading || !isActionable)
    }

    private var isLoading: Bool {
        viewModel.isFetching || viewModel.isPulling || viewModel.isPushing
    }

    /// What the button does in the current state.
    private var action: SyncAction {
        BranchSync.action(hasUpstream: viewModel.hasUpstream,
                          ahead: viewModel.syncAhead,
                          behind: viewModel.syncBehind)
    }

    /// Up to date is a state, not an action — the button says so and stays disabled.
    private var isActionable: Bool { action != .upToDate }

    private var title: String {
        switch action {
        case .publish: "Publish Branch"
        case .push: "Push (\(viewModel.syncAhead))"
        case .pull: "Pull (\(viewModel.syncBehind))"
        case .pullThenPush: "Sync (↓\(viewModel.syncBehind) ↑\(viewModel.syncAhead))"
        case .upToDate: "Up to date"
        }
    }

    private var iconName: String {
        switch action {
        case .publish, .push: "arrow.up.circle"
        case .pull: "arrow.down.circle"
        case .pullThenPush: "arrow.triangle.2.circlepath"
        case .upToDate: "checkmark.circle"
        }
    }

    private func performAction() {
        Task { await viewModel.sync() }
    }
}
