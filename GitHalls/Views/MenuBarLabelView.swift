//
//  MenuBarLabelView.swift
//  GitHalls
//

import SwiftUI

struct MenuBarLabelView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        Label {
            if viewModel.repositoryURL != nil {
                Text(viewModel.currentBranch ?? "…")
            }
        } icon: {
            Image(systemName: iconName)
        }
    }

    private var iconName: String {
        guard viewModel.repositoryURL != nil else { return "arrow.triangle.branch" }
        if !viewModel.changes.isEmpty { return "circle.fill" }
        if viewModel.syncAhead > 0 { return "arrow.up.circle.fill" }
        if viewModel.syncBehind > 0 { return "arrow.down.circle.fill" }
        return "checkmark.circle"
    }
}
