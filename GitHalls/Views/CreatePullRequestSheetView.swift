//
//  CreatePullRequestSheetView.swift
//  GitHalls
//

import SwiftUI

struct CreatePullRequestSheetView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// The sheet has something to say before the form is worth showing: whether
    /// this branch already has a pull request waiting.
    private enum Stage {
        case checking
        case alreadyOpen(PullRequestSummary)
        case form
    }

    @State private var stage: Stage = .checking
    @State private var title = ""
    @State private var description = ""
    @State private var baseBranch: String?

    /// What the draft filled in last, so a base change can refill the fields
    /// without overwriting anything the user typed over them.
    @State private var appliedDraft: PullRequestDraft?

    /// Set when the form was reached past an open pull request, which changes
    /// what GitHub will accept.
    @State private var supersedes: PullRequestSummary?

    private var remoteBranchNames: [String] {
        let names = viewModel.branches
            .filter(\.isRemote)
            .map { Branch.remoteShortName(from: $0.name) }
        return Array(Set(names)).sorted()
    }

    private var hasUserEdits: Bool {
        guard let appliedDraft else { return !title.isEmpty || !description.isEmpty }
        return title != appliedDraft.title || description != appliedDraft.body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch stage {
            case .checking:
                checking
            case .alreadyOpen(let pullRequest):
                alreadyOpen(pullRequest)
            case .form:
                form
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            await viewModel.loadBranches()
            // Asking GitHub first: filling in a title for a pull request that
            // already exists is work the user would only find out was wasted
            // once they pressed Create.
            if let pullRequest = await viewModel.openPullRequest() {
                stage = .alreadyOpen(pullRequest)
            } else {
                await applyDraft()
                stage = .form
            }
        }
    }

    private var checking: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Checking for an open pull request…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func alreadyOpen(_ pullRequest: PullRequestSummary) -> some View {
        Text("Pull Request Already Open")
            .font(.title2)
            .bold()

        VStack(alignment: .leading, spacing: 4) {
            Text("#\(pullRequest.number) \(pullRequest.title)")
                .font(.callout.weight(.medium))
                .lineLimit(2)

            if let branch = viewModel.currentBranch {
                Text("From \(branch)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

        Text("Opening it is almost always what you want. A second pull request from this branch has to target a different base branch.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Create New Anyway") {
                supersedes = pullRequest
                Task {
                    await applyDraft()
                    stage = .form
                }
            }
            Button("Open Pull Request") {
                if let url = URL(string: pullRequest.url) {
                    openURL(url)
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var form: some View {
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
        .onChange(of: baseBranch) {
            // The commits ahead — and so the title — depend on the base. Only
            // refill what the user has not made their own.
            guard !hasUserEdits else { return }
            Task { await applyDraft() }
        }

        if let supersedes {
            Label(
                "This branch already has #\(supersedes.number) open. Pick a different base branch, or GitHub will refuse the new one.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let currentBranch = viewModel.currentBranch {
            Text(sourceSummary(branch: currentBranch))
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

    /// Says where the title came from, so a branch name sitting in the field
    /// does not read as the app having failed to find anything better.
    private func sourceSummary(branch: String) -> String {
        switch appliedDraft?.commitCount {
        case 1: "From \(branch) · 1 commit"
        case .some(let count) where count > 1: "From \(branch) · \(count) commits"
        default: "From \(branch)"
        }
    }

    private func applyDraft() async {
        let draft = await viewModel.pullRequestDraft(base: baseBranch)
        appliedDraft = draft
        title = draft.title
        description = draft.body
    }
}
