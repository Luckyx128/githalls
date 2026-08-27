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
            ChangesSidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            DiffDetailView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.pickRepository()
                } label: {
                    Label("Open Repository...", systemImage: "folder.badge.plus")
                }
            }
        }
        .navigationTitle(viewModel.repositoryURL?.lastPathComponent ?? "GitHalls")
    }

}

#Preview {
    ContentView()
}
