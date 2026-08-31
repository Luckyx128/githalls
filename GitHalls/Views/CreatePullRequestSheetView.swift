//
//  CreatePullRequestSheetView.swift
//  GitHalls
//

import SwiftUI

struct CreatePullRequestSheetView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var baseBranch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Pull Request")
                .font(.title2)
                .bold()

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(4...8)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Base branch:")
                TextField("repository default", text: $baseBranch)
                    .textFieldStyle(.roundedBorder)
            }

            if let currentBranch = viewModel.currentBranch {
                Text("From \(currentBranch)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(viewModel.isCreatingPullRequest ? "Creating…" : "Create Pull Request") {
                    let trimmedBase = baseBranch.trimmingCharacters(in: .whitespaces)
                    Task {
                        await viewModel.createPullRequest(
                            title: title,
                            description: description,
                            base: trimmedBase.isEmpty ? nil : trimmedBase
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isCreatingPullRequest)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
