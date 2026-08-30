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
    @State private var showBranchSwitcher = false
    
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
            switch viewModel.sidebarMode {
            case .changes:
                DiffDetailView(viewModel: viewModel)
            case .history:
                CommitDetailView(viewModel: viewModel)
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
                    .disabled(viewModel.repositoryURL == nil)
            }
            ToolbarItem {
                Button {
                    viewModel.pickRepository()
                } label: {
                    Label("Open Repository...", systemImage: "folder.badge.plus")
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
