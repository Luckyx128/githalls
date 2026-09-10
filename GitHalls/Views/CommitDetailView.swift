//
//  CommitDetailView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 29/08/26.
//

import Foundation
import SwiftUI

struct CommitDetailView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        if viewModel.selectedCommitID == nil {
            ContentUnavailableView("Select a commit", systemImage: "clock")
        } else if viewModel.isLoadingCommitDetail {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = viewModel.selectedCommitDetail {
            VStack(alignment: .leading, spacing: 0) {
                CommitDetailHeader(commit: detail.commit, files: detail.files)
                    .padding(.vertical, 10)

                Divider()

                CommitFilesBrowser(viewModel: viewModel, detail: detail)
            }
        } else {
            ContentUnavailableView("No details to show", systemImage: "clock")
        }
    }
}

struct CommitDetailHeader: View {
    let commit: Commit
    var files: [CommitFile] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.summary)
                .font(.title3)
                .bold()
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Text(commit.authorName)
                Text("·")
                Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(commit.shortHash)
                    .font(.system(.body, design: .monospaced))

                if !files.isEmpty {
                    Text("·")
                    Text(files.count == 1 ? "1 file" : "\(files.count) files")

                    DiffLineCountBadges(
                        added: files.compactMap(\.addedLineCount).reduce(0, +),
                        removed: files.compactMap(\.removedLineCount).reduce(0, +)
                    )
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
}
