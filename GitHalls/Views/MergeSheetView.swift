//
//  MergeSheetView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 30/08/26.
//

import Foundation
import SwiftUI

struct MergeSheetView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBranch: String?

    private var targetBranch: String {
        viewModel.currentBranch ?? "?"
    }

    private var otherBranches: [Branch] {
        viewModel.branches.filter { !$0.isCurrent }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Merge into \"\(targetBranch)\"")
                .font(.title2)
                .bold()

            HStack(spacing: 12) {
                Picker("", selection: $selectedBranch) {
                    Text("Select a branch…").tag(String?.none)
                    ForEach(otherBranches) { branch in
                        Text(branch.name).tag(String?.some(branch.name))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                Text(targetBranch)
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }

            if let selectedBranch {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\"\(targetBranch)\" will be updated", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Text("Commits from \"\(selectedBranch)\" will be added to \"\(targetBranch)\". \"\(selectedBranch)\" itself won't change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Merge") {
                    if let selectedBranch {
                        Task {
                            await viewModel.merge(branch: selectedBranch)
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedBranch == nil || viewModel.isMerging)
            }
        }
        .padding(20)
        .frame(width: 380)
        .task {
            await viewModel.loadBranches()
        }
    }
}
