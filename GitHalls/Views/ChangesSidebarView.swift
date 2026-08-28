//
//  ChangesSidebarView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation
import SwiftUI

struct ChangesSidebarView: View {
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.repositoryURL == nil {
                    ContentUnavailableView("No Repository Open", systemImage: "folder", description: Text("Use \"Open Repository…\" to get started."))
                } else if viewModel.changes.isEmpty {
                    ContentUnavailableView("No Changes", systemImage: "checkmark.circle")
                } else {
                    List(viewModel.changes, selection: $viewModel.selectedChangeID) { change in
                        FileChangeRow(change: change) {
                            Task { await viewModel.toggleStage(for: change)}
                        }
                        .tag(change.id)
                    }
                }
            }
            if viewModel.repositoryURL != nil {
                Divider()
                CommitView(viewModel: viewModel)
            }
        }
        .onChange(of: viewModel.selectedChangeID) {
            Task { await viewModel.loadDiff() }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct FileChangeRow: View {
    let change: FileChange
    let onToggleStage: () -> Void
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { change.isStaged},
                set: {_ in onToggleStage() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            Label {
                Text(change.path)
                    .lineLimit(1)
            } icon: {
                Image(systemName: symbolName)
                    .foregroundStyle(symbolColor)
            }
        }
    }

    private var symbolName: String {
        switch change.status {
        case .modified: "pencil.circle.fill"
        case .added: "plus.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.turn.up.right"
        case .copied: "doc.on.doc.fill"
        case .untracked: "questionmark.circle.fill"
        case .unmerged: "exclamationmark.triangle.fill"
        }
    }

    private var symbolColor: Color {
        switch change.status {
        case .modified: .yellow
        case .added, .untracked: .green
        case .deleted: .red
        case .renamed, .copied: .blue
        case .unmerged: .orange
        }
    }
}
