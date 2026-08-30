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
                    if viewModel.repositoryURL == nil {
                        VStack(spacing: 16) {
                            ContentUnavailableView("No Repository Open", systemImage: "folder", description: Text("Use \"Open Repository…\" to get started."))

                            if !viewModel.recentRepositoryURLs.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("RECENT")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(viewModel.recentRepositoryURLs, id: \.self) { url in
                                        Button {
                                            viewModel.open(url)
                                        } label: {
                                            Label(url.lastPathComponent, systemImage: "clock")
                                                .lineLimit(1)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button("Remove from Recents", role: .destructive) {
                                                viewModel.forgetRecent(url)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }                } else if viewModel.changes.isEmpty {
                    ContentUnavailableView("No Changes", systemImage: "checkmark.circle")
                } else {
                    ChangesHeaderView(viewModel: viewModel)
                    Divider()
                    List(viewModel.changes, selection: $viewModel.selectedChangeID) { change in
                        FileChangeRow(change: change) {
                            Task { await viewModel.toggleStage(for: change)}
                        }
                        .tag(change.id)
                        .contextMenu {
                            Button("Discard Changes", role: .destructive) {
                                viewModel.requestDiscard(change)
                            }
                        }
                    }
                    .listStyle(.sidebar)
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
        .confirmationDialog(
            "Discard changes to \"\(viewModel.pendingDiscard?.fileName ?? "")\"?",
            isPresented: Binding(
                get: { viewModel.pendingDiscard != nil },
                set: { if !$0 { viewModel.cancelDiscard() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                Task { await viewModel.confirmDiscard() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDiscard()
            }
        } message: {
            Text("This cannot be undone.")
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
            
            StatusBadge(status: change.status)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(change.fileName)
                    .lineLimit(1)
                
                if !change.directoryPath.isEmpty {
                    Text(change.directoryPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 0)
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

struct StatusBadge: View {
    let status: FileChange.Status

    var body: some View {
        Text(letter)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(color.darker(bytTones: 3))
            .frame(width: 16, height: 16)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
    }

    private var letter: String {
        switch status {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .untracked: "U"
        case .unmerged: "!"
        }
    }

    private var color: Color {
        switch status {
        case .modified: .yellow
        case .added, .untracked: .green
        case .deleted: .red
        case .renamed, .copied: .blue
        case .unmerged: .orange
        }
    }
}

struct ChangesHeaderView: View {
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { viewModel.allStaged },
                set: { newValue in Task { await viewModel.setAllStaged(newValue) } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text("\(viewModel.changes.count) changed file\(viewModel.changes.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 4)
    }
}

#Preview {
    HStack {
        StatusBadge(status: .deleted)
    }.padding(10)
}

