//
//  ContentView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Bindable var jiraViewModel: JiraViewModel

    @State private var showBranchSwitcher = false
    @State private var sheet: ContentSheet?

    /// Graph mode hides the sidebar: a 280pt column showing nothing is dead
    /// space exactly when the graph needs the width most. The mode picker lives
    /// in the sidebar, so the toolbar keeps its own toggle — otherwise entering
    /// Graph would be a door that only opens one way.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Everything the toolbar can put on screen. One piece of state instead of
    /// four booleans, and one place to attach the presentations to — a `.sheet`
    /// hung off a toolbar item is presented by a view that may not be in the
    /// hierarchy when the menu holding it closes.
    private enum ContentSheet: String, Identifiable {
        case clone, merge, createPullRequest
        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                modePicker

                Divider()

                switch viewModel.sidebarMode {
                case .changes:
                    ChangesSidebarView(viewModel: viewModel)
                case .history:
                    HistorySidebarView(viewModel: viewModel)
                case .kanban:
                    KanbanSidebarView(viewModel: jiraViewModel)
                case .graph:
                    // The graph is the whole of Graph mode; the sidebar is here
                    // only so the picker above stays reachable.
                    Spacer()
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
                KanbanBoardView(viewModel: jiraViewModel)
            case .graph:
                GraphView(viewModel: viewModel)
            }
        }
        .onChange(of: viewModel.sidebarMode, initial: true) { _, mode in
            columnVisibility = mode == .graph ? .detailOnly : .all
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
        .toolbar { toolbarContent }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .clone:
                CloneSheetView(viewModel: viewModel)
            case .merge:
                MergeSheetView(viewModel: viewModel)
            case .createPullRequest:
                CreatePullRequestSheetView(viewModel: viewModel)
            }
        }
        .navigationTitle(viewModel.repositoryURL?.lastPathComponent ?? "GitHalls")
    }

    private var modePicker: some View {
        Picker("Mode", selection: $viewModel.sidebarMode) {
            Text("Changes").tag(SidebarMode.changes)
            Text("History").tag(SidebarMode.history)
            Text("Kanban").tag(SidebarMode.kanban)
            Text("Graph").tag(SidebarMode.graph)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .padding(8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading: where you are. The branch decides what every action to the
        // right of it does, so it reads before them rather than floating in the
        // middle of the window.
        //
        // No sidebar toggle of our own: `NavigationSplitView` puts one there
        // already, and it is the way back to the mode picker once Graph has
        // hidden the sidebar.
        ToolbarItem(placement: .navigation) {
            branchButton
        }

        // Trailing: what you do, most-used first.
        ToolbarItem {
            SyncButton(viewModel: viewModel)
                .buttonStyle(.glassProminent)
                .disabled(viewModel.repositoryURL == nil)
        }

        ToolbarItem {
            Button {
                sheet = .merge
            } label: {
                Label("Merge", systemImage: "arrow.triangle.merge")
            }
            .help("Merge a branch into this one")
            .disabled(viewModel.repositoryURL == nil)
        }

        ToolbarItem {
            Button {
                sheet = .createPullRequest
            } label: {
                Label("Create Pull Request", systemImage: "arrow.triangle.pull")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Create a pull request from this branch")
            .disabled(viewModel.repositoryURL == nil)
        }

        ToolbarItem {
            repositoryMenu
        }
    }

    @ViewBuilder
    private var branchButton: some View {
        if viewModel.repositoryURL != nil {
            Button {
                showBranchSwitcher = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(viewModel.currentBranch ?? "Branch")
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Switch branch")
            .popover(isPresented: $showBranchSwitcher) {
                BranchSwitcherView(viewModel: viewModel)
            }
        }
    }

    /// Opening, closing, and everything that acts on the repository as a whole.
    ///
    /// Never disabled as a menu: "Open Repository…" is the one thing that has
    /// to work when no repository is open, so the items inside it that need one
    /// say so individually.
    private var repositoryMenu: some View {
        Menu {
            Button("Open Repository…") {
                viewModel.pickRepository()
            }
            Button("Clone Repository…") {
                sheet = .clone
            }

            if !viewModel.recentRepositoryURLs.isEmpty {
                Menu("Open Recent") {
                    ForEach(viewModel.recentRepositoryURLs, id: \.self) { url in
                        Button {
                            viewModel.open(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "clock")
                        }
                    }
                }
            }

            Divider()

            Button("Refresh") {
                Task { await viewModel.refreshStatus() }
            }
            .disabled(viewModel.repositoryURL == nil)

            Button("Reveal in Finder") {
                if let url = viewModel.repositoryURL {
                    QuickActions.revealInFinder(url)
                }
            }
            .disabled(viewModel.repositoryURL == nil)

            Button("Open in Terminal") {
                if let url = viewModel.repositoryURL {
                    QuickActions.openInTerminal(url)
                }
            }
            .disabled(viewModel.repositoryURL == nil)

            Button("Open in Editor") {
                if let url = viewModel.repositoryURL {
                    Task { await QuickActions.openInEditor(url) }
                }
            }
            .disabled(viewModel.repositoryURL == nil)

            Divider()

            Button("Close Repository") {
                viewModel.closeRepository()
            }
            .disabled(viewModel.repositoryURL == nil)
        } label: {
            Label("Repository", systemImage: "ellipsis.circle")
        }
    }
}

#Preview {
    ContentView(viewModel: RepositoryViewModel(), jiraViewModel: JiraViewModel())
}
