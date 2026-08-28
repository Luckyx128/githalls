//
//  CommitView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 28/08/26.
//

import Foundation
import SwiftUI

struct CommitView: View {
    @Bindable var viewModel: RepositoryViewModel

    private var hasStagedChanges: Bool {
        viewModel.changes.contains { $0.isStaged }
    }

    private var commitButtonTitle: String {
        if viewModel.isCommitting {
            return "Committing…"
        }
        if let branch = viewModel.currentBranch, !branch.isEmpty {
            return "Commit to \(branch)"
        }
        return "Commit"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Summary", text: $viewModel.commitSummary)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $viewModel.commitDescription, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await viewModel.commit() }
            } label: {
                HStack {
                    if viewModel.isCommitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(commitButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.commitSummary.isEmpty || !hasStagedChanges || viewModel.isCommitting)
        }
        .padding(8)
    }
}
