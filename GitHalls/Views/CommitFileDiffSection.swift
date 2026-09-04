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
                DiffView(diff: fileDiff, presentation: .intrinsic(maxHeight: 2000))
            }
        }
        .background(Color.gray.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
        .padding(.horizontal)
    }
}
