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
    @State private var selectedType: ConventionalCommitType?
    @State private var scope: String = ""
    @State private var showTypeReference = false
    @State private var showIdentitySwitcher = false
    @State private var coAuthorText = ""
    @State private var showCoAuthorField = false
    @State private var coAuthorInvalid = false

    private var identityLabel: String {
        guard let identity = viewModel.currentIdentity else { return "Set identity" }
        return identity.label.isEmpty ? identity.name : identity.label
    }

    private var stagedChanges: [FileChange] {
        viewModel.changes.filter(\.isStaged)
    }

    private var hasStagedChanges: Bool {
        !stagedChanges.isEmpty
    }

    /// A merge waiting to be committed has nothing staged to show — git already
    /// holds the result — so the staged-files rule cannot be the only gate.
    private var canCommit: Bool {
        hasStagedChanges || viewModel.isMergeReadyToCommit || viewModel.isAmending
    }

    /// Known people not yet credited, for the "+ Co-author" menu.
    private var suggestions: [CoAuthor] {
        let mine = viewModel.currentIdentity?.email.lowercased()
        return viewModel.knownAuthors
            .filter { !viewModel.commitCoAuthors.contains($0) && $0.email.lowercased() != mine }
            .prefix(30)
            .map { $0 }
    }

    private func submitCoAuthor() {
        let text = coAuthorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showCoAuthorField = false
            return
        }
        if viewModel.addCoAuthor(text) {
            coAuthorText = ""
            coAuthorInvalid = false
            showCoAuthorField = false
        } else {
            coAuthorInvalid = true
        }
    }

    private var commitButtonTitle: String {
        if viewModel.isCommitting {
            return "Committing…"
        }
        if viewModel.isAmending { return "Amend" }
        let verb = viewModel.isMergeReadyToCommit ? "Commit merge" : "Commit"
        if let branch = viewModel.currentBranch, !branch.isEmpty {
            return "\(verb) to \(branch)"
        }
        return verb
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.canRewriteHead, let head = viewModel.headCommit {
                undoBanner(head)
            }

            Button {
                showIdentitySwitcher = true
            } label: {
                Label(identityLabel, systemImage: "person.crop.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showIdentitySwitcher) {
                GitIdentitySwitcherView(viewModel: viewModel)
            }

            HStack(spacing: 6) {
                Picker("", selection: $selectedType) {
                    Text("Type").tag(ConventionalCommitType?.none)
                    ForEach(ConventionalCommitType.allCases) { type in
                        Text(type.rawValue).tag(ConventionalCommitType?.some(type))
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: selectedType) { applyPrefix() }

                TextField("scope", text: $scope)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit { applyPrefix() }

                Button {
                    showTypeReference = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showTypeReference) {
                    ConventionalCommitReferenceView()
                }

                Spacer()

                Button {
                    applySuggestion()
                } label: {
                    Label("Suggest", systemImage: "wand.and.stars")
                }
                .buttonStyle(.glass)
                .disabled(!hasStagedChanges)
            }

            TextField("Summary", text: $viewModel.commitSummary)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $viewModel.commitDescription, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            coAuthorSection

            if viewModel.canRewriteHead {
                Toggle("Amend last commit", isOn: Binding(
                    get: { viewModel.isAmending },
                    set: { enabled in Task { await viewModel.setAmending(enabled) } }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Rewrite the last commit instead of adding a new one")
            }

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
            .buttonStyle(.glassProminent)
            .disabled(viewModel.commitSummary.isEmpty || !canCommit || viewModel.isCommitting || viewModel.isStaging)
        }
        .padding(8)
    }

    /// The last commit, with a way back while it is still only local.
    private func undoBanner(_ head: HeadCommit) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
            Text(head.summary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button("Undo") {
                Task { await viewModel.undoLastCommit() }
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isCommitting)
            .help("Undo the last commit and keep its changes staged")
        }
        .font(.caption)
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var coAuthorSection: some View {
        ForEach(viewModel.commitCoAuthors) { author in
            HStack(spacing: 4) {
                Image(systemName: "person.2")
                Text(author.display)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    viewModel.removeCoAuthor(author)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if showCoAuthorField {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name <email>", text: $coAuthorText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitCoAuthor() }
                    .onChange(of: coAuthorText) { coAuthorInvalid = false }
                if coAuthorInvalid {
                    Text("Use the form Name <email>")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }

        HStack(spacing: 8) {
            Menu {
                ForEach(suggestions) { author in
                    Button(author.display) { viewModel.addCoAuthor(author.display) }
                }
                if !suggestions.isEmpty { Divider() }
                Button("Other…") { showCoAuthorField = true }
            } label: {
                Label("Co-author", systemImage: "plus")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .task(id: viewModel.repositoryURL) {
            await viewModel.loadKnownAuthors()
        }
    }

    private func applyPrefix() {
        guard let selectedType else { return }
        let trimmedScope = scope.trimmingCharacters(in: .whitespaces)
        let scopePart = trimmedScope.isEmpty ? "" : "(\(trimmedScope))"
        let prefix = "\(selectedType.rawValue)\(scopePart): "
        
        if let colonRange = viewModel.commitSummary.range(of: ": ") {
            let rest = viewModel.commitSummary[colonRange.upperBound...]
            viewModel.commitSummary = prefix + rest
        } else if viewModel.commitSummary.isEmpty {
            viewModel.commitSummary = prefix
        } else {
            viewModel.commitSummary = prefix + viewModel.commitSummary
        }
    }

    private func applySuggestion() {
        scope = ConventionalCommitSuggester.suggestedScope(for: stagedChanges) ?? ""
        Task {
            selectedType = await viewModel.suggestedCommitType()
            applyPrefix()
        }
    }
}


#Preview {
    CommitView(viewModel:RepositoryViewModel() )
}
