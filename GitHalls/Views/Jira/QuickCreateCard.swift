//
//  QuickCreateCard.swift
//  GitHalls
//

import SwiftUI

/// "+ Add issue" at the foot of a column; expands to a one-line field. Return
/// creates the issue in this column's status, Escape closes it.
struct QuickCreateCard: View {
    let status: String
    @Bindable var viewModel: JiraViewModel

    @State private var model = JiraQuickCreate()
    @State private var isEditing = false
    @FocusState private var focused: Bool
    @State private var sheetPrefill: CreateIssuePrefill?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                HStack(spacing: 6) {
                    TextField("What needs to be done?", text: $model.summary)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .disabled(model.isCreating)
                        .onSubmit { Task { await create() } }
                        .onExitCommand { close() }

                    if model.isCreating { ProgressView().controlSize(.small) }
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            } else {
                Button {
                    isEditing = true
                    focused = true
                } label: {
                    Label("Add issue", systemImage: "plus")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Add issue to \(status)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // The project wants more than a title: the full form, with the title,
        // project, type and this column already in it.
        .sheet(item: $sheetPrefill) { prefill in
            CreateIssueSheet(jiraViewModel: viewModel, projectKey: prefill.projectKey, prefill: prefill) { key in
                guard let target = prefill.targetStatus else { return }
                Task {
                    await JiraQuickCreate.place(key, in: target, board: viewModel)
                    // After the move, or the reload would fetch the old status.
                    viewModel.invalidate()
                }
            }
        }
    }

    private func create() async {
        // Stay open on success: adding several in a row is the common case.
        if case .needsSheet(let prefill) = await model.submit(status: status, board: viewModel) {
            sheetPrefill = prefill
            model.summary = ""
        }
        focused = true
    }

    private func close() {
        model.summary = ""
        model.errorMessage = nil
        isEditing = false
    }
}
