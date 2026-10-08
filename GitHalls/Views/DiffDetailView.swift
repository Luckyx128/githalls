//
//  DiffDetailView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation
import SwiftUI

struct DiffDetailView: View {
    let viewModel: RepositoryViewModel

    private var readmePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let name = viewModel.readmeFileName {
                    Label(name, systemImage: "doc.text")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                MarkdownView(blocks: viewModel.readme)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Same for the same file, side and whitespace setting, so a reload keeps
    /// the scroll position and expanding context does too.
    private var placeIdentity: String {
        "\(viewModel.selectedChangeID ?? "")|\(viewModel.selectedDiffSide)|\(viewModel.ignoreWhitespace)"
    }

    var body: some View {
        if viewModel.selectedChangeID == nil {
            // Nothing selected is the moment the repository is opened and the
            // moment a branch is switched into — which is exactly when its
            // README is worth reading.
            if viewModel.readme.isEmpty {
                ContentUnavailableView("Select a file", systemImage: "doc.text")
            } else {
                readmePane
            }
        } else if let diff = viewModel.currentDiff, diff.isBinary {
            // git has no text for this one, so the diff pane shows the file
            // itself instead of a notice saying it cannot.
            ScrollView {
                FilePreviewView(viewModel: viewModel,
                                path: diff.path,
                                before: .revision("HEAD"),
                                after: .workingTree)
            }
        } else if let diff = viewModel.currentDiff {
            // Checked before `isLoadingDiff` so a redundant reload of the
            // already-selected file (e.g. triggered by a status refresh on
            // window activation) keeps this DiffView's identity stable and
            // just updates it in place, instead of tearing down and
            // recreating the underlying NSTextView — recreating it can race
            // AppKit's layout pass and leave the pane permanently blank.
            VStack(spacing: 0) {
                DiffFileHeader(viewModel: viewModel, diff: diff)
                Divider()
                DiffView(diff: viewModel.displayDiff(for: diff),
                         interaction: viewModel.diffInteraction(for: diff),
                         placeIdentity: placeIdentity,
                         onExpand: { gap, direction in viewModel.expandContext(gap: gap, direction) })
            }
                .overlay(alignment: .bottom) {
                    if viewModel.diffInteraction(for: diff)?.mode == .lines {
                        LineSelectionBar(viewModel: viewModel)
                    }
                }
                .confirmationDialog(
                    "Discard \(viewModel.pendingLineDiscard?.lineCount ?? 0) selected line(s) in \"\(viewModel.pendingLineDiscard?.fileName ?? "")\"?",
                    isPresented: Binding(
                        get: { viewModel.pendingLineDiscard != nil },
                        set: { if !$0 { viewModel.cancelLineDiscard() } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Discard Changes", role: .destructive) {
                        Task { await viewModel.confirmLineDiscard() }
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.cancelLineDiscard()
                    }
                } message: {
                    Text("This cannot be undone.")
                }
        } else if viewModel.isLoadingDiff {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No diff to show", systemImage: "doc.text")
        }
    }
}

/// Stays put above the scrolling diff: which file, how much changed, and the
/// whitespace switch.
private struct DiffFileHeader: View {
    @Bindable var viewModel: RepositoryViewModel
    let diff: FileDiff

    var body: some View {
        HStack(spacing: 10) {
            Text(diff.path)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.head)
                .help(diff.path)

            if !diff.isBinary, diff.addedLineCount + diff.removedLineCount > 0 {
                HStack(spacing: 6) {
                    Text("+\(diff.addedLineCount)").foregroundStyle(.green)
                    Text("\u{2212}\(diff.removedLineCount)").foregroundStyle(.red)
                }
                .font(.caption.monospacedDigit())
            }

            Spacer(minLength: 8)

            if viewModel.isStagingBlockedByWhitespace {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .help("Show whitespace changes to stage parts of this file")
            }

            Toggle("Hide whitespace changes", isOn: $viewModel.ignoreWhitespace)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help(viewModel.isStagingBlockedByWhitespace
                      ? "Show whitespace changes to stage parts of this file"
                      : "Hide whitespace changes (staging parts of a file needs them shown)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// The floating bar that appears once lines are picked in the gutter. Picking
/// changes nothing in git; every button here is an explicit act.
private struct LineSelectionBar: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        let count = viewModel.diffSelection.lines.count
        if count > 0 {
            HStack(spacing: 12) {
                Text("^[\(count) line](inflect: true) selected")
                    .monospacedDigit()

                Text("\u{00B7}").foregroundStyle(.secondary)

                if viewModel.selectedDiffSide == .staged {
                    Button("Unstage") { Task { await viewModel.unstageSelectedLines() } }
                } else {
                    Button("Stage") { Task { await viewModel.stageSelectedLines() } }
                    if viewModel.selectedChange?.status != .untracked {
                        Button("Discard", role: .destructive) { viewModel.requestDiscardSelectedLines() }
                    }
                }

                Button {
                    viewModel.diffSelection.clear()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Clear selection (Esc)")
                .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isStaging)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
