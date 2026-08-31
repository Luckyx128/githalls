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
    @State private var baseBranch: String?

    private var remoteBranchNames: [String] {
        let names = viewModel.branches
            .filter(\.isRemote)
            .map { Branch.remoteShortName(from: $0.name) }
        return Array(Set(names)).sorted()
    }

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

            Picker("Base branch:", selection: $baseBranch) {
                Text("Repository default").tag(String?.none)
                ForEach(remoteBranchNames, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
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
                    Task {
                        await viewModel.createPullRequest(
                            title: title,
                            description: description,
                            base: baseBranch
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
        .task {
            await viewModel.loadBranches()
        }
    }
}
