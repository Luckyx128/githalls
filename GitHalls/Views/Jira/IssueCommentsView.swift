//
//  IssueCommentsView.swift
//  GitHalls
//

import SwiftUI

/// The comment thread under an issue: read, add, edit and delete. Comments
/// live in the view model so every window on the issue agrees; this view only
/// holds what is being typed.
struct IssueCommentsView: View {
    let issueKey: String
    @Bindable var jiraViewModel: JiraViewModel

    @State private var newComment = ""
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var loadError: String?
    @State private var editingID: String?
    @State private var editText = ""
    @State private var deleting: JiraComment?

    private var comments: [JiraComment] { jiraViewModel.commentsByIssue[issueKey] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Comments", systemImage: "text.bubble").font(.headline).labelStyle(IssueSectionLabelStyle())
                if !comments.isEmpty { Text("\(comments.count)").foregroundStyle(.secondary) }
                if isLoading { ProgressView().controlSize(.small) }
            }

            if let loadError {
                Text(loadError).font(.callout).foregroundStyle(.red)
            }

            ForEach(comments) { comment in
                row(comment)
            }

            composer
        }
        .task(id: issueKey) { await load() }
        .confirmationDialog("Delete this comment?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { comment in
            Button("Delete", role: .destructive) {
                Task { await jiraViewModel.deleteComment(on: issueKey, id: comment.id) }
            }
        }
    }

    private func row(_ comment: JiraComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.author?.displayName ?? "Unknown").font(.callout.bold())
                Text(timestamp(comment)).font(.callout).foregroundStyle(.secondary)
                Spacer()

                if !comment.isPending, editingID != comment.id, isMine(comment) {
                    Button { startEditing(comment) } label: { Image(systemName: "pencil") }
                        .help("Edit comment")
                    Button { deleting = comment } label: { Image(systemName: "trash") }
                        .help("Delete comment")
                }
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)

            if editingID == comment.id {
                TextEditor(text: $editText)
                    .frame(minHeight: 70)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                HStack {
                    Button("Cancel") { editingID = nil }
                    Button("Save") {
                        Task {
                            if await jiraViewModel.editComment(on: issueKey, id: comment.id, text: editText) {
                                editingID = nil
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Save the edit (⌘Return)")
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text(comment.body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .opacity(comment.isPending ? 0.5 : 1)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $newComment)
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))

            HStack {
                Button("Comment") {
                    Task {
                        isPosting = true
                        let text = newComment
                        // Cleared only on success, or a refused comment is lost.
                        if await jiraViewModel.addComment(to: issueKey, text: text) {
                            newComment = ""
                            loadError = nil
                        } else {
                            loadError = jiraViewModel.actionMessage
                        }
                        isPosting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                // Hands ⌘Return to the Save of a comment being edited.
                .keyboardShortcut(editingID == nil ? KeyboardShortcut(.return, modifiers: .command) : nil)
                .help("Post the comment (⌘Return)")
                .disabled(isPosting || newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isPosting { ProgressView().controlSize(.small) }
            }
        }
    }

    private func isMine(_ comment: JiraComment) -> Bool {
        // Unknown until /myself answers; Jira refuses an edit that isn't yours anyway.
        jiraViewModel.myAccountID == nil || comment.author?.accountID == jiraViewModel.myAccountID
    }

    private func startEditing(_ comment: JiraComment) {
        editText = comment.body
        editingID = comment.id
    }

    private func timestamp(_ comment: JiraComment) -> String {
        guard let date = comment.created else { return "" }
        let base = date.formatted(date: .abbreviated, time: .shortened)
        return comment.updated.map { $0 > date.addingTimeInterval(1) } == true ? base + " (edited)" : base
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do { try await jiraViewModel.loadComments(for: issueKey) } catch { loadError = error.localizedDescription }
        isLoading = false
    }
}
