//
//  CommitFilesBrowser.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 10/09/26.
//

import Foundation
import SwiftUI

/// What a commit changed: the files down the left, the diff of the one picked
/// on the right.
///
/// Stacking every diff in one column meant scrolling past a thousand lines of
/// one file to reach the name of the next. A list answers "what did this touch"
/// on its own, and only the file being read costs a `git show`.
struct CommitFilesBrowser: View {
    let viewModel: RepositoryViewModel
    let detail: CommitDetail

    @State private var pickedFileID: CommitFile.ID?

    /// Falls back to the first file so the pane is never blank on arrival, and
    /// so a commit reached with a stale pick still shows something.
    private var selectedFile: CommitFile? {
        detail.files.first { $0.id == pickedFileID } ?? detail.files.first
    }

    private var selection: Binding<CommitFile.ID?> {
        Binding(get: { selectedFile?.id }, set: { pickedFileID = $0 })
    }

    var body: some View {
        if detail.files.isEmpty {
            ContentUnavailableView(
                "No File Changes",
                systemImage: "doc",
                description: Text("This commit does not change any file.")
            )
        } else {
            HSplitView {
                fileList
                    .frame(minWidth: 190, idealWidth: 260, maxWidth: 460)

                diffPane
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var fileList: some View {
        List(detail.files, selection: selection) { file in
            CommitFileRow(file: file)
                .tag(file.id)
        }
        .listStyle(.inset)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var diffPane: some View {
        if let file = selectedFile {
            VStack(alignment: .leading, spacing: 0) {
                diffHeader(for: file)

                Divider()

                CommitFileDiffPane(
                    viewModel: viewModel,
                    commitHash: detail.commit.hash,
                    file: file
                )
            }
        }
    }

    @ViewBuilder
    private func diffHeader(for file: CommitFile) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.path)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                // A rename that also changed lines reads as an unrelated file
                // unless the old name is on screen next to the new one.
                if let originalPath = file.originalPath {
                    Text("renamed from \(originalPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if !file.isBinary {
                DiffLineCountBadges(
                    added: file.addedLineCount ?? 0,
                    removed: file.removedLineCount ?? 0
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct CommitFileRow: View {
    let file: CommitFile

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(status: file.status)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !file.directoryPath.isEmpty {
                    Text(file.directoryPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 4)

            if file.isBinary {
                Image(systemName: "doc.viewfinder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                DiffLineCountBadges(
                    added: file.addedLineCount ?? 0,
                    removed: file.removedLineCount ?? 0
                )
            }
        }
        .padding(.vertical, 2)
        .help(file.path)
    }
}

/// The diff of the picked file, fetched when the pick changes.
///
/// Keeps its own state rather than the view model's: the pane is the only thing
/// that wants this text, and reloading is exactly "the selection moved".
private struct CommitFileDiffPane: View {
    let viewModel: RepositoryViewModel
    let commitHash: String
    let file: CommitFile

    @State private var diff: FileDiff?
    @State private var isLoading = true

    var body: some View {
        Group {
            if file.isBinary {
                ScrollView {
                    FilePreviewView(
                        viewModel: viewModel,
                        path: file.path,
                        before: .revision("\(commitHash)^"),
                        after: .revision(commitHash)
                    )
                }
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let diff {
                DiffView(diff: diff, presentation: .fill)
            } else {
                ContentUnavailableView(
                    "Diff Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("git could not produce a diff for this file.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: Load(commitHash: commitHash, fileID: file.id)) {
            guard !file.isBinary else { return }
            isLoading = true
            let loaded = await viewModel.commitFileDiff(hash: commitHash, file: file)
            guard !Task.isCancelled else { return }
            diff = loaded
            isLoading = false
        }
    }

    /// What a reload is for: the same pane is reused as the pick moves.
    private struct Load: Equatable {
        let commitHash: String
        let fileID: CommitFile.ID
    }
}
