//
//  CreateIssueSheet.swift
//  GitHalls
//

import SwiftUI

/// New issue: project and type first (they decide which fields Jira wants),
/// then summary, a markdown description, and the optional fields.
struct CreateIssueSheet: View {
    @Bindable var jiraViewModel: JiraViewModel
    var projectKey: String?
    var onCreated: (String) -> Void = { _ in }

    @State private var model: JiraCreateIssueViewModel
    @State private var userQuery = ""
    @State private var hasDueDate = false
    @Environment(\.dismiss) private var dismiss

    init(jiraViewModel: JiraViewModel,
         projectKey: String? = nil,
         authoring: any JiraIssueAuthoring = JiraAuthoringFactory.make(),
         onCreated: @escaping (String) -> Void = { _ in }) {
        self.jiraViewModel = jiraViewModel
        self.projectKey = projectKey
        self.onCreated = onCreated
        _model = State(initialValue: JiraCreateIssueViewModel(authoring: authoring, projectKey: projectKey))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Create Issue")
                .font(.title3.bold())
                .padding(20)

            Form {
                Section {
                    projectPicker
                    typePicker
                }
                Section {
                    TextField("Summary", text: $model.summary)
                    descriptionEditor
                }
                Section {
                    optionalFields
                }
                if !model.dynamicFields.isEmpty {
                    Section("Required by this project") {
                        ForEach(model.dynamicFields) { dynamicField($0) }
                    }
                }
            }
            .formStyle(.grouped)

            footer
        }
        .frame(width: 520, height: 640)
        .task { await model.load() }
    }

    // MARK: - Pickers

    private var projectPicker: some View {
        Picker("Project", selection: Binding(
            get: { model.selectedProject },
            set: { project in Task { await model.select(project: project) } }
        )) {
            ForEach(model.projects) { Text("\($0.name) (\($0.key))").tag(Optional($0)) }
        }
    }

    private var typePicker: some View {
        Picker("Issue type", selection: Binding(
            get: { model.selectedType },
            set: { type in Task { await model.select(type: type) } }
        )) {
            ForEach(model.issueTypes) { Text($0.name).tag(Optional($0)) }
        }
    }

    private var descriptionEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description (Markdown)")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $model.descriptionMarkdown)
                .font(.body.monospaced())
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
        }
    }

    // MARK: - Optional fields

    @ViewBuilder
    private var optionalFields: some View {
        if model.supportsPriority, !model.priorities.isEmpty {
            Picker("Priority", selection: $model.priorityID) {
                Text("Default").tag(String?.none)
                ForEach(model.priorities) { Text($0.label).tag(Optional($0.id)) }
            }
        }

        assigneeField

        if model.supportsLabels {
            TextField("Labels", text: $model.labelsText, prompt: Text("comma or space separated"))
        }

        if model.supportsParent {
            TextField(model.parentRequired ? "Parent (required)" : "Parent / epic",
                      text: $model.parentKey, prompt: Text("PROJ-123"))
        }

        Toggle("Due date", isOn: $hasDueDate)
            .onChange(of: hasDueDate) { _, on in model.dueDate = on ? Date() : nil }
        if hasDueDate {
            DatePicker("Due", selection: Binding(get: { model.dueDate ?? Date() },
                                                 set: { model.dueDate = $0 }),
                       displayedComponents: .date)
        }
    }

    private var assigneeField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Assignee", text: $userQuery, prompt: Text("Search people"))
                    .onChange(of: userQuery) { _, query in
                        Task {
                            try? await Task.sleep(for: .milliseconds(250))
                            guard query == userQuery else { return }
                            await model.searchUsers(query)
                        }
                    }
                if let assignee = model.assignee {
                    Text(assignee.displayName).foregroundStyle(.secondary)
                    Button("Clear") { model.assignee = nil }.buttonStyle(.link)
                }
            }

            if !userQuery.isEmpty {
                ForEach(model.userResults.prefix(5)) { user in
                    Button(user.displayName) {
                        model.assignee = user
                        userQuery = ""
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
        }
    }

    @ViewBuilder
    private func dynamicField(_ field: JiraCreateField) -> some View {
        let binding = Binding(get: { model.extraValues[field.key] ?? "" },
                              set: { model.extraValues[field.key] = $0 })

        if !field.allowed.isEmpty {
            Picker(field.name, selection: binding) {
                Text("Choose…").tag("")
                ForEach(field.allowed) { Text($0.label).tag($0.id) }
            }
        } else {
            TextField(field.name, text: binding,
                      prompt: field.kind == .date ? Text("yyyy-MM-dd") : nil)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if !model.missing.isEmpty {
                Text("Needs: " + model.missing.joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if model.isLoading || model.isSubmitting { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task {
                        guard let key = await model.submit() else { return }
                        jiraViewModel.invalidate()
                        onCreated(key)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSubmit)
            }
        }
        .padding(20)
    }
}
