//
//  HistorySidebarView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 29/08/26.
//

import Foundation
import SwiftUI

struct HistorySidebarView: View {
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        Group {
            if viewModel.commits.isEmpty {
                ContentUnavailableView("No Commits", systemImage: "clock")
            } else {
                List(viewModel.commits, selection: $viewModel.selectedCommitID) { commit in
                    CommitRow(commit: commit, isUnpushed: viewModel.unpushedCommitHashes.contains(commit.hash))
                        .tag(commit.id)
                        .contextMenu {
                            if viewModel.canRewriteHead, viewModel.headCommit?.hash == commit.hash {
                                Button("Undo Commit") {
                                    Task { await viewModel.undoLastCommit() }
                                }
                                .disabled(viewModel.isCommitting)
                            }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .task(id: viewModel.repositoryURL) {
            await viewModel.loadCommits()
        }
        .onChange(of: viewModel.selectedCommitID) {
            Task { await viewModel.loadCommitDetail() }
        }
    }
}

struct CommitRow: View {
    let commit: Commit
    let isUnpushed: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.summary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(commit.compactAuthorsLabel)
                    .help(commit.coAuthors.isEmpty ? "" : commit.allAuthorsLabel)
                Text("·")
                Text(Self.relativeFormatter.localizedString(for: commit.date, relativeTo: Date()))
                Spacer()
                if isUnpushed {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(Color.accentColor)
                        .help("Not pushed yet")
                }
                Text(commit.shortHash)
                    .font(.system(.caption, design: .monospaced))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
