//
//  SetUpstreamSheetView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import SwiftUI

struct SetUpstreamSheetView: View {
    @Bindable var viewModel: RepositoryViewModel
    let branch: String
    @Environment(\.dismiss) private var dismiss

    @State private var selected: String?
    @State private var current: String?

    private var remoteBranches: [Branch] {
        viewModel.branches.filter(\.isRemote)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Upstream for \"\(branch)\"")
                .font(.title2)
                .bold()

            if remoteBranches.isEmpty {
                Text("This repository has no remote branches yet. Push \"\(branch)\" first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("", selection: $selected) {
                    Text("Select a remote branch…").tag(String?.none)
                    ForEach(remoteBranches) { remote in
                        Text(remote.name).tag(String?.some(remote.name))
                    }
                }
                .labelsHidden()

                Text(current.map { "Currently tracking \($0)." } ?? "This branch tracks nothing yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Set Upstream") {
                    if let selected {
                        Task {
                            await viewModel.setUpstream(of: branch, to: selected)
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil || viewModel.isMutatingBranch)
            }
        }
        .padding(20)
        .frame(width: 380)
        .task {
            await viewModel.loadBranches()
            current = await viewModel.upstream(of: branch)
            selected = current
        }
    }
}
