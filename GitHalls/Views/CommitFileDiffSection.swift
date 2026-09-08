//
//  CommitFileDiffSection.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 30/08/26.
//

import Foundation
import SwiftUI

struct CommitFileDiffSection: View {
    let fileDiff: FileDiff

    /// Only set where the commit is known — the preview needs a revision to
    /// read the bytes from, which a diff alone does not carry.
    var viewModel: RepositoryViewModel?
    var commitHash: String?

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(fileDiff.path)
                    .font(.headline)

                Spacer()
            }
            .padding(8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                if fileDiff.isBinary, let viewModel, let commitHash {
                    FilePreviewView(viewModel: viewModel,
                                    path: fileDiff.path,
                                    before: .revision("\(commitHash)^"),
                                    after: .revision(commitHash))
                } else {
                    DiffView(diff: fileDiff, presentation: .intrinsic(maxHeight: 2000))
                }
            }
        }
        .background(Color.gray.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
        .padding(.horizontal)
    }
}
