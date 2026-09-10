//
//  CommitInlineDetailView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import SwiftUI

/// What a commit changed, opened underneath its own row in the graph.
///
/// The gutter keeps drawing the lanes that pass this point, so the graph does
/// not visibly break in half while a commit is open.
struct CommitInlineDetailView: View {
    @Bindable var viewModel: RepositoryViewModel
    let row: GraphRow
    let laneCount: Int
    let gutterWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GraphLaneContinuation(edges: row.continuingEdges, laneCount: laneCount)
                .frame(width: gutterWidth)

            detail
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.trailing, 8)
        }
        .background(Color.gray.opacity(0.05))
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .onExitCommand { viewModel.selectedCommitID = nil }
    }

    @ViewBuilder
    private var detail: some View {
        if viewModel.isLoadingCommitDetail {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading changes…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let detail = viewModel.selectedCommitDetail,
                  detail.commit.hash == row.commit.hash {
            VStack(alignment: .leading, spacing: 10) {
                header(for: detail)

                if detail.files.isEmpty {
                    Text("No file changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Inline in the graph the detail cannot take the height it
                    // likes: the rows below it are still the graph, and pushing
                    // them off screen is what a side pane would have done.
                    CommitFilesBrowser(viewModel: viewModel, detail: detail)
                        .frame(height: 420)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                }
            }
        } else {
            Text("No details to show.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func header(for detail: CommitDetail) -> some View {
        let added = detail.addedLineCount
        let removed = detail.removedLineCount

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Selecting a row is what opens this; without something to click,
            // there is no way back to a compact list.
            Button {
                viewModel.selectedCommitID = nil
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Collapse")

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.commit.summary)
                    .font(.headline)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Text(detail.commit.authorName)
                    Text("·")
                    Text(detail.commit.date.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(detail.commit.shortHash)
                        .font(.system(.caption, design: .monospaced))
                    Text("·")
                    Text(detail.files.count == 1 ? "1 file" : "\(detail.files.count) files")

                    DiffLineCountBadges(added: added, removed: removed)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}
