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

    /// One for the app: Clockify runs one timer per user, and every issue
    /// window has to show the same one.
    @State private var clockifyViewModel = ClockifyViewModel()

    /// Where git and Jira meet: the branch's issue, pushes as comments, offers.
    @State private var issueLink: IssueLinkCoordinator

    init() {
        let repository = RepositoryViewModel()
        let jira = JiraViewModel()
        let clockify = ClockifyViewModel()
        _viewModel = State(initialValue: repository)
        _jiraViewModel = State(initialValue: jira)
        _clockifyViewModel = State(initialValue: clockify)
        _issueLink = State(initialValue: IssueLinkCoordinator(jira: jira, repository: repository, clockify: clockify))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel, jiraViewModel: jiraViewModel)
                .environment(issueLink)
        }

        // One window per issue: opening the same card twice brings its window
        // forward instead of stacking a twin.
        WindowGroup(id: "issue", for: JiraIssue.self) { $issue in
            if let issue {
                IssueWindowView(
                    issue: issue,
                    jiraViewModel: jiraViewModel,
                    repositoryViewModel: viewModel,
                    clockifyViewModel: clockifyViewModel
                )
                .environment(issueLink)
            }
        }
        Settings {
            TabView {
                GeneralSettingsView()
                    .tabItem { Label("General", systemImage: "gearshape") }
                GitIdentitiesSettingsView()
                    .tabItem { Label("Git Identities", systemImage: "person.2") }
                JiraSettingsView()
                    .tabItem { Label("Jira", systemImage: "checklist") }
                ClockifySettingsView(clockify: clockifyViewModel)
                    .tabItem { Label("Clockify", systemImage: "timer") }
                CodeSettingsView()
                    .tabItem { Label("Code", systemImage: "chevron.left.forwardslash.chevron.right") }
                EditorSettingsView()
                    .tabItem { Label("Editors", systemImage: "terminal") }
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
