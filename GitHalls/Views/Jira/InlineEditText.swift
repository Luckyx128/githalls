//
//  InlineEditText.swift
//  GitHalls
//

import SwiftUI

/// Text that turns into an editor when asked to. Save is Return for a line,
/// the button for a block; Escape and Cancel put the old text back. The save
/// closure answers whether Jira took it, and the editor only closes when it did.
struct InlineEditText<Display: View>: View {
    let text: String
    var multiline = false
    var placeholder = ""
    let onSave: (String) async -> Bool
    @ViewBuilder let display: () -> Display

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            editor
        } else {
            HStack(alignment: .top, spacing: 6) {
                display()
                Button {
                    draft = text
                    isEditing = true
                    focused = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .foregroundStyle(.secondary)
                .help("Edit")
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if multiline {
                TextEditor(text: $draft)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .focused($focused)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
            } else {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { Task { await save() } }
            }

            HStack {
                Button("Cancel", action: cancel)
                Button("Save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !canSave)
                if isSaving { ProgressView().controlSize(.small) }
                if multiline { Text("Markdown").font(.callout).foregroundStyle(.secondary) }
            }
        }
        .onExitCommand(perform: cancel)
    }

    private var canSave: Bool {
        // A summary cannot be emptied; a description can.
        (multiline || !draft.trimmingCharacters(in: .whitespaces).isEmpty) && draft != text
    }

    private func save() async {
        guard canSave, !isSaving else { return }

        isSaving = true
        if await onSave(draft) { isEditing = false }
        isSaving = false
    }

    private func cancel() {
        isEditing = false
    }
}
