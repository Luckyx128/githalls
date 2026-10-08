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
    @State private var hasDueDate = false
    @Environment(\.dismiss) private var dismiss

    init(jiraViewModel: JiraViewModel,
         projectKey: String? = nil,
         prefill: CreateIssuePrefill? = nil,
         authoring: any JiraIssueAuthoring = JiraAuthoringFactory.make(),
         onCreated: @escaping (String) -> Void = { _ in }) {
        self.jiraViewModel = jiraViewModel
        self.projectKey = projectKey
        self.onCreated = onCreated
        _model = State(initialValue: JiraCreateIssueViewModel(authoring: authoring, projectKey: projectKey, prefill: prefill))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Create Issue")
                .font(.title3.bold())
                .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    projectPicker
                    typePicker

                    FieldBlock(title: "Summary", required: true, error: model.fieldErrors["summary"]) {
                        TextField("", text: $model.summary)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: model.summary) { model.clearError("summary") }
                    }

                    if model.isShown("description") { descriptionEditor }
                    standardFields

                    ForEach(model.dynamicFields) { dynamicField($0) }
                }
                .padding(.horizontal, 20)
            }

            footer
        }
        .frame(width: 540, height: 680)
        .task { await model.load() }
    }

    // MARK: - Pickers

    private var projectPicker: some View {
        FieldBlock(title: "Project", required: true, error: model.fieldErrors["project"]) {
            Picker("", selection: Binding(
                get: { model.selectedProject },
                set: { project in Task { await model.select(project: project) } }
            )) {
                ForEach(model.projects) { Text("\($0.name) (\($0.key))").tag(Optional($0)) }
            }
            .labelsHidden()
        }
    }

    private var typePicker: some View {
        FieldBlock(title: "Issue type", required: true, error: model.fieldErrors["issuetype"]) {
            Picker("", selection: Binding(
                get: { model.selectedType },
                set: { type in Task { await model.select(type: type) } }
            )) {
                ForEach(model.issueTypes) { Text($0.name).tag(Optional($0)) }
            }
            .labelsHidden()
        }
    }

    private var descriptionEditor: some View {
        FieldBlock(title: "Description (Markdown)", required: model.isRequired("description"),
                   error: model.fieldErrors["description"]) {
            TextEditor(text: $model.descriptionMarkdown)
                .font(.body.monospaced())
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                .onChange(of: model.descriptionMarkdown) { model.clearError("description") }
        }
    }

    // MARK: - Built-in optional fields

    @ViewBuilder
    private var standardFields: some View {
        if model.isShown("priority"), !model.priorityOptions.isEmpty {
            FieldBlock(title: "Priority", required: model.isRequired("priority"), error: model.fieldErrors["priority"]) {
                Picker("", selection: $model.priorityID) {
                    Text(model.isRequired("priority") ? "Choose…" : "Default").tag(String?.none)
                    ForEach(model.priorityOptions) { Text($0.label).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .onChange(of: model.priorityID) { model.clearError("priority") }
            }
        }

        if model.isShown("assignee") {
            FieldBlock(title: "Assignee", required: model.isRequired("assignee"), error: model.fieldErrors["assignee"]) {
                UserPickerField(
                    selected: Binding(get: { model.assignee.map { [$0] } ?? [] },
                                      set: { model.assignee = $0.first }),
                    search: { await model.findUsers($0) },
                    onChange: { model.clearError("assignee") })
            }
        }

        if model.isShown("labels") {
            FieldBlock(title: "Labels", required: model.isRequired("labels"), error: model.fieldErrors["labels"]) {
                TextField("", text: $model.labelsText, prompt: Text("comma or space separated"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.labelsText) { model.clearError("labels") }
            }
        }

        if !model.componentOptions.isEmpty {
            FieldBlock(title: "Components", required: model.isRequired("components"), error: model.fieldErrors["components"]) {
                multiChoice(model.componentOptions,
                            selection: Binding(get: { model.componentIDs }, set: { model.componentIDs = $0 }),
                            key: "components")
            }
        }

        if model.supportsParent {
            FieldBlock(title: model.parentRequired ? "Parent" : "Parent / epic", required: model.parentRequired,
                       error: model.fieldErrors["parent"]) {
                TextField("", text: $model.parentKey, prompt: Text("PROJ-123"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.parentKey) { model.clearError("parent") }
            }
        }

        if model.isShown("duedate") {
            FieldBlock(title: "Due date", required: model.isRequired("duedate"), error: model.fieldErrors["duedate"]) {
                HStack {
                    Toggle("Set", isOn: $hasDueDate)
                        .onChange(of: hasDueDate) { _, on in
                            model.dueDate = on ? Date() : nil
                            model.clearError("duedate")
                        }
                    if hasDueDate {
                        DatePicker("", selection: Binding(get: { model.dueDate ?? Date() },
                                                          set: { model.dueDate = $0 }),
                                   displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: - Required custom fields

    private func dynamicField(_ field: JiraCreateField) -> some View {
        FieldBlock(title: field.name, required: true, error: model.fieldErrors[field.key]) {
            dynamicInput(field)
        }
    }

    @ViewBuilder
    private func dynamicInput(_ field: JiraCreateField) -> some View {
        let text = Binding(get: { model.extraValues[field.key] ?? "" },
                           set: { model.extraValues[field.key] = $0; model.clearError(field.key) })

        switch JiraCreateIssueViewModel.input(for: field) {
        case .select:
            Picker("", selection: text) {
                Text("Choose…").tag("")
                ForEach(field.allowed) { Text($0.label).tag($0.id) }
            }
            .labelsHidden()
        case .multiSelect:
            multiChoice(field.allowed,
                        selection: Binding(get: { model.extraSelections[field.key] ?? [] },
                                           set: { model.extraSelections[field.key] = $0 }),
                        key: field.key)
        case .user:
            UserPickerField(
                selected: Binding(get: { model.extraUsers[field.key] ?? [] },
                                  set: { model.extraUsers[field.key] = $0 }),
                allowsMany: field.kind == .userList,
                search: { await model.findUsers($0) },
                onChange: { model.clearError(field.key) })
        case .team:
            TeamPickerField(field: field, teamID: text,
                            search: { await model.findTeams($0, for: field) })
        case .markdown:
            TextEditor(text: text)
                .font(.body.monospaced())
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
        case .date:
            DatePicker("", selection: Binding(
                get: { Self.day.date(from: text.wrappedValue) ?? Date() },
                set: { text.wrappedValue = Self.day.string(from: $0) }
            ), displayedComponents: .date)
            .labelsHidden()
            .onAppear { if text.wrappedValue.isEmpty { text.wrappedValue = Self.day.string(from: Date()) } }
        case .duration:
            TextField("", text: text, prompt: Text("2h 30m"))
                .textFieldStyle(.roundedBorder)
        case .number:
            TextField("", text: text).textFieldStyle(.roundedBorder)
        case .dateTime:
            TextField("", text: text, prompt: Text("2026-01-31T09:00:00.000+0000"))
                .textFieldStyle(.roundedBorder)
        case .labels:
            TextField("", text: text, prompt: Text("comma or space separated"))
                .textFieldStyle(.roundedBorder)
        case .text:
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func multiChoice(_ options: [JiraFieldOption], selection: Binding<Set<String>>, key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options) { option in
                Toggle(option.label, isOn: Binding(
                    get: { selection.wrappedValue.contains(option.id) },
                    set: { on in
                        if on { selection.wrappedValue.insert(option.id) } else { selection.wrappedValue.remove(option.id) }
                        model.clearError(key)
                    }))
            }
        }
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
