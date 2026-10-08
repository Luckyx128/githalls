//
//  IssueWorklogView.swift
//  GitHalls
//

import SwiftUI

/// Time logged on an issue, and a line to log more. "1h 30m", "2h", "45m" and
/// "1d" are understood; a day is eight hours, as Jira counts it.
struct IssueWorklogView: View {
    let issueKey: String
    @Bindable var jiraViewModel: JiraViewModel

    @State private var duration = ""
    @State private var note = ""
    @State private var loadError: String?
    @State private var isLogging = false
    @State private var deleting: JiraWorklog?

    private var worklogs: [JiraWorklog] { jiraViewModel.worklogsByIssue[issueKey] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Work log").font(.headline)
                let total = worklogs.reduce(0) { $0 + $1.timeSpentSeconds }
                if total > 0 { Text(JiraWorklog.format(seconds: total)).foregroundStyle(.secondary) }
            }

            if let loadError { Text(loadError).font(.callout).foregroundStyle(.red) }

            ForEach(worklogs) { log in
                HStack(spacing: 8) {
                    Text(log.timeSpent).bold()
                    Text(log.author?.displayName ?? "").foregroundStyle(.secondary)
                    if let started = log.started {
                        Text(started.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                    }
                    Text(log.comment).lineLimit(1)
                    Spacer()
                    if !log.isPending {
                        Button { deleting = log } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .help("Delete this entry")
                    }
                }
                .font(.callout)
                .opacity(log.isPending ? 0.5 : 1)
            }

            HStack {
                TextField("1h 30m", text: $duration).frame(width: 90)
                    .onSubmit { Task { await log() } }
                TextField("What did you do? (optional)", text: $note)
                    .onSubmit { Task { await log() } }
                Button("Log") { Task { await log() } }
                    .disabled(isLogging || Self.seconds(from: duration) == nil)
            }
            .textFieldStyle(.roundedBorder)
        }
        .confirmationDialog("Delete this work log entry?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { log in
            Button("Delete", role: .destructive) {
                Task { await jiraViewModel.deleteWorklog(on: issueKey, id: log.id) }
            }
        }
        .task(id: issueKey) {
            do { try await jiraViewModel.loadWorklogs(for: issueKey) } catch { loadError = error.localizedDescription }
        }
    }

    private func log() async {
        guard !isLogging, let seconds = Self.seconds(from: duration) else { return }

        isLogging = true
        defer { isLogging = false }

        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if await jiraViewModel.logWork(on: issueKey, seconds: seconds, comment: text.isEmpty ? nil : text) {
            duration = ""
            note = ""
            loadError = nil
        } else {
            loadError = jiraViewModel.actionMessage
        }
    }

    static func seconds(from text: String) -> Int? { JiraDuration.seconds(from: text) }
}
