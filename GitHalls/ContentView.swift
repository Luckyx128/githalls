//
//  ContentView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = RepositoryViewModel()
    @State private var jiraViewModel = JiraViewModel()
    @State private var showBranchSwitcher = false
    @State private var showMergeSheet = false
    @State private var showCloneSheet = false
    @State private var showCreatePRSheet = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                            Picker("Mode", selection: $viewModel.sidebarMode) {
                                Text("Changes").tag(SidebarMode.changes)
                                Text("History").tag(SidebarMode.history)
                                Text("Kanban").tag(SidebarMode.kanban)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .padding(8)

                            switch viewModel.sidebarMode {
                            case .changes:
                                ChangesSidebarView(viewModel: viewModel)
                            case .history:
                                HistorySidebarView(viewModel: viewModel)
                            case .kanban:
                                KanbanSidebarView(viewModel: jiraViewModel)
                            }
                        }
                        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            switch viewModel.sidebarMode {
            case .changes:
                DiffDetailView(viewModel: viewModel)
            case .history:
                CommitDetailView(viewModel: viewModel)
            case .kanban:
                IssueDetailView(jiraViewModel: jiraViewModel, repositoryViewModel: viewModel)
            }
        }
        .task {
            viewModel.openMostRecentRepositoryIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await viewModel.fetch()
                if viewModel.selectedChangeID != nil {
                    await viewModel.loadDiff()
                }
            }
        }
        .toolbar {
            ToolbarItem {
                SyncButton(viewModel: viewModel)
                    .buttonStyle(.glassProminent)
                    .disabled(viewModel.repositoryURL == nil)
            }
            ToolbarItem {
                Menu {
                    Button("Open Repository…") {
                        viewModel.pickRepository()
                    }
                    Button("Clone Repository…") {
                        showCloneSheet = true
                    }
                    if !viewModel.recentRepositoryURLs.isEmpty {
                        Divider()
                        ForEach(viewModel.recentRepositoryURLs, id: \.self) { url in
                            Button {
                                viewModel.open(url)
                            } label: {
                                Label(url.lastPathComponent, systemImage: "clock")
                            }
                        }
                    }
                } label: {
                    Label("Open Repository...", systemImage: "folder.badge.plus")
                }
                .sheet(isPresented: $showCloneSheet) {
                    CloneSheetView(viewModel: viewModel)
                }
            }
            ToolbarItem {
                Button {
                    showMergeSheet = true
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .disabled(viewModel.repositoryURL == nil)
                .sheet(isPresented: $showMergeSheet) {
                    MergeSheetView(viewModel: viewModel)
                }
            }
            ToolbarItem {
                Button {
                    showBranchSwitcher = true
                } label: {
                    Label(viewModel.currentBranch ?? "Branch", systemImage: "arrow.triangle.branch")
                }
                .disabled(viewModel.repositoryURL == nil)
                .popover(isPresented: $showBranchSwitcher) {
                    BranchSwitcherView(viewModel: viewModel)
                }
            }
            ToolbarItem {
                Button {
                    showCreatePRSheet = true
                } label: {
                    Label("Create Pull Request", systemImage: "arrow.triangle.pull")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.repositoryURL == nil)
                .sheet(isPresented: $showCreatePRSheet) {
                    CreatePullRequestSheetView(viewModel: viewModel)
                }
            }
            ToolbarItem {
                Button {
                    Task { await viewModel.refreshStatus() }
                } label: {
                    Label ("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.repositoryURL == nil)
            }
            ToolbarItem {
                Button {
                    viewModel.closeRepository()  
                } label: {
                    Label("Close Repository", systemImage: "xmark.circle")
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
