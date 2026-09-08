//
//  KanbanSidebarView.swift
//  GitHalls
//

import SwiftUI

/// Which query the board runs. It used to be a JQL text field: most people
/// never write JQL, and the ones who do want to keep what they wrote — so the
/// presets are the list, and a custom query is saved beside them.
struct KanbanSidebarView: View {
    @Bindable var viewModel: JiraViewModel

    @State private var editing: JiraQuery?
    @State private var isAdding = false

    private var presets: [JiraQuery] { viewModel.queries.filter(\.isBuiltIn) }
    private var custom: [JiraQuery] { viewModel.queries.filter { !$0.isBuiltIn } }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isConfigured {
                queryList
                Divider()
                addButton
            } else {
                ContentUnavailableView {
                    Label("Jira Not Connected", systemImage: "link.badge.plus")
                } description: {
                    Text("Connect your Jira account to see your queries here.")
                } actions: {
                    SettingsLink { Text("Open Settings") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isAdding) {
            QueryEditorView(title: "New Query", name: "", jql: "") { name, jql in
                viewModel.addQuery(name: name, jql: jql)
            }
        }
        .sheet(item: $editing) { query in
            QueryEditorView(title: "Edit Query", name: query.name, jql: query.jql) { name, jql in
                viewModel.updateQuery(query, name: name, jql: jql)
            }
        }
    }

    private var queryList: some View {
        List(selection: Binding(
            get: { viewModel.selectedQuery.id },
            set: { id in
                guard let query = viewModel.queries.first(where: { $0.id == id }) else { return }
                viewModel.select(query)
            }
        )) {
            Section("Queries") {
                ForEach(presets) { query in
                    QueryRow(query: query).tag(query.id)
                }
            }

            if !custom.isEmpty {
                Section("My Queries") {
                    ForEach(custom) { query in
                        QueryRow(query: query)
                            .tag(query.id)
                            .contextMenu {
                                Button("Edit…") { editing = query }
                                Button("Delete", role: .destructive) { viewModel.removeQuery(query) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("Add Query", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .padding(8)
    }
}

private struct QueryRow: View {
    let query: JiraQuery

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(query.name)
                    .lineLimit(1)
                if !query.isBuiltIn {
                    Text(query.jql)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: icon)
        }
        .help(query.jql)
    }

    /// A sprint preset, a person preset, or the user's own filter.
    private var icon: String {
        switch query.id {
        case _ where !query.isBuiltIn: "line.3.horizontal.decrease.circle"
        case JiraQueryPresets.activeSprintID, JiraQueryPresets.mySprintWorkID: "flag"
        case JiraQueryPresets.recentlyUpdatedID: "clock"
        default: "person"
        }
    }
}

/// Name + JQL. The same sheet writes a new query and edits an existing one.
private struct QueryEditorView: View {
    let title: String
    @State var name: String
    @State var jql: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            TextField("Name", text: $name, prompt: Text("Bugs in my project"))
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $jql)
                .font(.system(.body, design: .monospaced))
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))

            Text("Jira Query Language, exactly as in Jira's own search. currentUser() and openSprints() work here too.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(name, jql)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    name.trimmingCharacters(in: .whitespaces).isEmpty
                    || jql.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
