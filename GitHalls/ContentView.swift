//
//  ContentView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var viewModel = RepositoryViewModel()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                            Picker("Mode", selection: $viewModel.sidebarMode) {
                                Text("Changes").tag(SidebarMode.changes)
                                Text("History").tag(SidebarMode.history)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .padding(8)

                            switch viewModel.sidebarMode {
                            case .changes:
                                ChangesSidebarView(viewModel: viewModel)
                            case .history:
                                HistorySidebarView(viewModel: viewModel)
                            }
                        }
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            DiffDetailView(viewModel: viewModel)
        }
        .task {
            viewModel.openMostRecentRepositoryIfNeeded()
        }
        .task {
            viewModel.openMostRecentRepositoryIfNeeded()
            if let url = viewModel.repositoryURL {
                let service = GitService()
                if let commits = try? await service.log(at: url) {
                    for commit in commits.prefix(5) {
                        print("\(commit.shortHash) - \(commit.summary) (\(commit.authorName), \(commit.date))")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.pickRepository()
                } label: {
                    Label("Open Repository...", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem {
                Button {
                    viewModel.closeRepository()
                } label: {
                    Label("Close Repository", systemImage: "xmark.circle")
                }
                .disabled(viewModel.repositoryURL == nil)
            }
            ToolbarItem {
                Button {
                    Task { await viewModel.refreshStatus() }
                } label: {
                    Label ("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.repositoryURL == nil)
            }
            
        }
        .navigationTitle(viewModel.repositoryURL?.lastPathComponent ?? "GitHalls")
    }

}



#Preview {
    ContentView()
}
