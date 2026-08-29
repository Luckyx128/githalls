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
                    CommitRow(commit: commit)
                        .tag(commit.id)
                }
                .listStyle(.sidebar)
            }
        }
        .task(id: viewModel.repositoryURL) {
            await viewModel.loadCommits()
        }
    }
}

struct CommitRow: View {
    let commit: Commit

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
                Text(commit.authorName)
                Text("·")
                Text(Self.relativeFormatter.localizedString(for: commit.date, relativeTo: Date()))
                Spacer()
                Text(commit.shortHash)
                    .font(.system(.caption, design: .monospaced))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
