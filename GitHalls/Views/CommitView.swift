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
            .disabled(viewModel.commitSummary.isEmpty || !hasStagedChanges || viewModel.isCommitting || viewModel.isStaging)
        }
        .padding(8)
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
