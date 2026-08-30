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

    private var isActionable: Bool {
        !viewModel.hasUpstream || viewModel.syncAhead > 0 || viewModel.syncBehind > 0
    }

    private var title: String {
        if !viewModel.hasUpstream { return "Publish Branch" }
        if viewModel.syncAhead > 0 { return "Push (\(viewModel.syncAhead))" }
        if viewModel.syncBehind > 0 { return "Pull (\(viewModel.syncBehind))" }
        return "Up to date"
    }

    private var iconName: String {
        if !viewModel.hasUpstream || viewModel.syncAhead > 0 { return "arrow.up.circle" }
        if viewModel.syncBehind > 0 { return "arrow.down.circle" }
        return "checkmark.circle"
    }

    private func performAction() {
        if !viewModel.hasUpstream || viewModel.syncAhead > 0 {
            Task { await viewModel.push() }
        } else if viewModel.syncBehind > 0 {
            Task { await viewModel.pull() }
        }
    }
}
