//
//  GraphRefChips.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import SwiftUI

/// The refs pointing at a commit. Capped, because a commit carrying eight of
/// them would otherwise squeeze the summary to nothing.
struct GraphRefChips: View {
    let refs: [GitRef]
    var visibleLimit = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(refs.prefix(visibleLimit)) { ref in
                chip(for: ref)
            }
            if refs.count > visibleLimit {
                Text("+\(refs.count - visibleLimit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .help(refs.map(\.name).joined(separator: ", "))
    }

    @ViewBuilder
    private func chip(for ref: GitRef) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol(for: ref.kind))
            Text(ref.name)
                .lineLimit(1)
        }
        .font(.caption2)
        .fontWeight(ref.kind == .head ? .semibold : .regular)
        .foregroundStyle(foreground(for: ref.kind))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background(for: ref.kind), in: Capsule())
    }

    private func symbol(for kind: GitRef.Kind) -> String {
        switch kind {
        case .head: "arrowtriangle.right.fill"
        case .localBranch: "arrow.triangle.branch"
        case .remoteBranch: "cloud"
        case .tag: "tag"
        }
    }

    private func foreground(for kind: GitRef.Kind) -> Color {
        switch kind {
        case .head: .white
        case .localBranch: .accentColor
        case .remoteBranch: .secondary
        case .tag: .yellow
        }
    }

    private func background(for kind: GitRef.Kind) -> AnyShapeStyle {
        switch kind {
        case .head: AnyShapeStyle(Color.accentColor)
        case .localBranch: AnyShapeStyle(Color.accentColor.opacity(0.18))
        case .remoteBranch: AnyShapeStyle(.quaternary)
        case .tag: AnyShapeStyle(Color.yellow.opacity(0.20))
        }
    }
}
