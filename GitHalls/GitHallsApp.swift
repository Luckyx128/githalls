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

    /// Held here, not in ContentView: the issue windows are scenes of their own
    /// and need the same Jira state the board is showing.
    @State private var jiraViewModel = JiraViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, jiraViewModel: jiraViewModel)
        }

        // One window per issue: opening the same card twice brings its window
        // forward instead of stacking a twin.
        WindowGroup(id: "issue", for: JiraIssue.self) { $issue in
            if let issue {
                IssueWindowView(
                    issue: issue,
                    jiraViewModel: jiraViewModel,
                    repositoryViewModel: viewModel
                )
            }
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
