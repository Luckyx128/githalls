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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CommitDetailHeader(commit: detail.commit)

                    ForEach(detail.fileDiffs, id: \.path) { fileDiff in
                        CommitFileDiffSection(fileDiff: fileDiff)
                    }
                }
                .padding(.vertical)
            }
        } else {
            ContentUnavailableView("No details to show", systemImage: "clock")
        }
    }
}

struct CommitDetailHeader: View {
    let commit: Commit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.summary)
                .font(.title3)
                .bold()

            HStack(spacing: 8) {
                Text(commit.authorName)
                Text("·")
                Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(commit.shortHash)
                    .font(.system(.body, design: .monospaced))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
}
