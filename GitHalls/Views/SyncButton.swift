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
        Group {
            if viewModel.isFetching || viewModel.isPulling || viewModel.isPushing {
                ProgressView()
                    .controlSize(.small)
            } else if !viewModel.hasUpstream {
                Button {
                    Task { await viewModel.push() }
                } label: {
                    Label("Publish Branch", systemImage: "arrow.up.circle")
                }
            } else if viewModel.syncAhead > 0 {
                Button {
                    Task { await viewModel.push() }
                } label: {
                    Label("Push (\(viewModel.syncAhead))", systemImage: "arrow.up.circle")
                }
            } else if viewModel.syncBehind > 0 {
                Button {
                    Task { await viewModel.pull() }
                } label: {
                    Label("Pull (\(viewModel.syncBehind))", systemImage: "arrow.down.circle")
                }
            } else {
                Label("Up to date", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
