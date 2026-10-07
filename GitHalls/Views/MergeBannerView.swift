//
//  MergeBannerView.swift
//  GitHalls
//

import SwiftUI

/// The bar that owns a merge from the moment it stops until it is committed.
///
/// Conflicts get resolved in an editor, not here, so the useful thing this can
/// do is notice when the resolving is finished and offer the one command that
/// ends the merge — which git otherwise only exposes on the command line.
struct MergeBannerView: View {
    @Bindable var viewModel: RepositoryViewModel
    @State private var confirmingAbort = false

    private var operation: MergeState.Operation { viewModel.mergeState?.operation ?? .merge }
    private var markerPaths: [String] { viewModel.mergeState?.markerPaths ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.isMergeReadyToCommit {
                readyHeader
            } else {
                conflictHeader
            }

            if !markerPaths.isEmpty {
                Label(
                    "^[\(markerPaths.count) file](inflect: true) still contain conflict markers",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                if viewModel.isMergeReadyToCommit {
                    finalizeButton

                    Button("Edit Message") {
                        viewModel.useEditableMergeMessage()
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .disabled(viewModel.mergeState?.preparedMessage == nil)
                } else {
                    if !ExternalEditors.installed.isEmpty {
                        Menu("Open All in") {
                            ForEach(ExternalEditors.installed) { editor in
                                Button(editor.name) { viewModel.openAllConflicts(in: editor) }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .font(.callout)
                    }

                    Button("Mark All Resolved") {
                        Task { await viewModel.markAllResolved() }
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .disabled(viewModel.isStaging)
                }

                Spacer()

                Button(operation.abortTitle, role: .destructive) {
                    confirmingAbort = true
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .disabled(viewModel.isFinalizingMerge)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary)
        .confirmationDialog(
            "Abort this \(operation.noun)?",
            isPresented: $confirmingAbort,
            titleVisibility: .visible
        ) {
            Button(operation.abortTitle, role: .destructive) {
                Task { await viewModel.abortMerge() }
            }
            Button("Keep Resolving", role: .cancel) {}
        } message: {
            Text("The branch goes back to where it was. Every conflict you resolved is discarded.")
        }
    }

    private var conflictHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text("^[\(viewModel.conflictedChanges.count) file](inflect: true) with conflicts")
                .font(.callout)

            Spacer()
        }
    }

    private var readyHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text("All conflicts resolved")
                    .font(.callout.weight(.medium))

                Spacer()
            }

            if let summary = viewModel.preparedMergeSummary {
                Text(viewModel.commitSummary.isEmpty ? summary : viewModel.commitSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var finalizeButton: some View {
        Button {
            Task { await viewModel.finalizeMerge() }
        } label: {
            HStack(spacing: 4) {
                if viewModel.isFinalizingMerge {
                    ProgressView().controlSize(.small)
                }
                Text(viewModel.isFinalizingMerge ? "Committing…" : operation.finishTitle)
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.small)
        .disabled(viewModel.isFinalizingMerge || !markerPaths.isEmpty)
    }
}
