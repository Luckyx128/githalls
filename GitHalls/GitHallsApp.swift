//
//  GitHallsApp.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import SwiftUI

@main
struct GitHallsApp: App {
    @State private var viewModel = RepositoryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        Settings {
            TabView {
                GitIdentitiesSettingsView()
                    .tabItem { Label("Git Identities", systemImage: "person.2") }
                JiraSettingsView()
                    .tabItem { Label("Jira", systemImage: "checklist") }
            }
        }
        MenuBarExtra {
            MenuBarPanelView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
