//
//  IssueDetailView.swift
//  GitHalls
//

import SwiftUI

struct IssueDetailView: View {
    @Bindable var jiraViewModel: JiraViewModel
    @Bindable var repositoryViewModel: RepositoryViewModel
    @State private var branchName = ""

    var body: some View {
        if let issue = jiraViewModel.selectedIssue {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.key)
                        .font(.title2)
                        .fontDesign(.monospaced)
                        .bold()
                    Text(issue.summary)
                        .font(.title3)
                }

                HStack(spacing: 8) {
                    Label(issue.status, systemImage: "circle.fill")
                    if let priority = issue.priority {
                        Text("·")
                        Text(priority)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Create branch from this issue")
                        .font(.headline)

                    HStack {
                        TextField("Branch name", text: $branchName)
                            .textFieldStyle(.roundedBorder)
                        Button("Create Branch") {
                            Task { await repositoryViewModel.createBranch(named: branchName) }
                        }
                        .disabled(
                            branchName.trimmingCharacters(in: .whitespaces).isEmpty
                            || repositoryViewModel.repositoryURL == nil
                            || repositoryViewModel.isSwitchingBranch
                        )
                    }

                    if let repoURL = repositoryViewModel.repositoryURL {
                        Text("Will create in \(repoURL.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Open a repository first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: issue.id) {
                branchName = jiraViewModel.suggestedBranchName(for: issue)
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { repositoryViewModel.errorMessage != nil },
                    set: { if !$0 { repositoryViewModel.errorMessage = nil } }
                )
            ) {
                Button("OK") { repositoryViewModel.errorMessage = nil }
            } message: {
                Text(repositoryViewModel.errorMessage ?? "")
            }
        } else {
            ContentUnavailableView("No Issue Selected", systemImage: "rectangle.on.rectangle")
        }
    }
}
