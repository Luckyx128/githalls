//
//  CreateIssueFields.swift
//  GitHalls
//

import SwiftUI

/// A label with a red asterisk when required, the control, and Jira's message
/// for this field underneath.
struct FieldBlock<Content: View>: View {
    let title: String
    var required = false
    var error: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                if required {
                    Text("*").font(.callout).foregroundStyle(.red).accessibilityLabel("required")
                }
            }
            content()
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Search-as-you-type people picker, for one person or several.
struct UserPickerField: View {
    @Binding var selected: [JiraUser]
    var allowsMany = false
    let search: (String) async -> [JiraUser]
    var onChange: () -> Void = {}

    @State private var query = ""
    @State private var results: [JiraUser] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !selected.isEmpty {
                HStack {
                    ForEach(selected) { user in
                        Button {
                            selected.removeAll { $0.id == user.id }
                            onChange()
                        } label: {
                            Label(user.displayName, systemImage: "xmark.circle.fill")
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Remove \(user.displayName)")
                    }
                }
            }

            if allowsMany || selected.isEmpty {
                TextField("Search people", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .task(id: query) {
                        guard !query.isEmpty else { results = []; return }
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        results = await search(query)
                    }

                ForEach(results.prefix(5)) { user in
                    Button(user.displayName) {
                        if allowsMany {
                            if !selected.contains(where: { $0.id == user.id }) { selected.append(user) }
                        } else {
                            selected = [user]
                        }
                        query = ""
                        results = []
                        onChange()
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
        }
    }
}

/// Team: a menu when createmeta lists the teams, a search box otherwise.
struct TeamPickerField: View {
    let field: JiraCreateField
    @Binding var teamID: String
    let search: (String) async -> [JiraFieldOption]
    var onChange: () -> Void = {}

    @State private var query = ""
    @State private var results: [JiraFieldOption] = []
    @State private var chosenName: String?

    private var options: [JiraFieldOption] { field.allowed }

    var body: some View {
        if !options.isEmpty {
            Picker("", selection: Binding(get: { teamID }, set: { teamID = $0; onChange() })) {
                Text("Choose…").tag("")
                ForEach(options) { Text($0.label).tag($0.id) }
            }
            .labelsHidden()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if !teamID.isEmpty {
                    Button {
                        teamID = ""
                        chosenName = nil
                        onChange()
                    } label: {
                        Label(chosenName ?? teamID, systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Clear team")
                } else {
                    TextField("Search teams", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .task(id: query) {
                            try? await Task.sleep(for: .milliseconds(250))
                            guard !Task.isCancelled else { return }
                            results = await search(query)
                        }
                    ForEach(results.prefix(8)) { team in
                        Button(team.label) {
                            teamID = team.id
                            chosenName = team.label
                            onChange()
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
            }
        }
    }
}
