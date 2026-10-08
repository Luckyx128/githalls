//
//  IssueRelationsView.swift
//  GitHalls
//

import SwiftUI

/// Parent, subtasks and links of one issue. `issue` is the window's copy; the
/// writes patch the board's, and `onChange` hands the fresh relations back.
struct IssueRelationsView: View {
    @Binding var issue: JiraIssue
    @Bindable var jiraViewModel: JiraViewModel

    @State private var linkTypes: [JiraLinkType] = []
    @State private var choice: LinkChoice?
    @State private var linkKey = ""
    @State private var subtaskTitle = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    /// "blocks" and "is blocked by" are two ends of one type; the picker shows
    /// the phrase and remembers which end it was.
    struct LinkChoice: Hashable, Identifiable {
        let type: JiraLinkType
        let direction: JiraIssueLink.Direction
        var id: String { type.id + direction.rawValue }
        var label: String { direction == .outward ? type.outward : type.inward }
    }

    private var choices: [LinkChoice] {
        linkTypes.flatMap { [LinkChoice(type: $0, direction: .outward), LinkChoice(type: $0, direction: .inward)] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let parentKey = issue.parentKey {
                HStack(spacing: 6) {
                    Text("Parent").font(.headline)
                    Text(parentKey).fontDesign(.monospaced)
                    Text(issue.parentSummary ?? "").foregroundStyle(.secondary).lineLimit(1)
                }
            }

            subtasksSection
            linksSection

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
        }
        .task { linkTypes = (try? await jiraViewModel.client().linkTypes()) ?? [] }
    }

    // MARK: - Subtasks

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subtasks").font(.headline)

            ForEach(issue.subtasks ?? []) { ref in refRow(ref, prefix: nil) }

            HStack {
                TextField("Add a subtask", text: $subtaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await addSubtask() } }
                    .disabled(isWorking)
            }
        }
    }

    private func addSubtask() async {
        let title = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isWorking = true
        defer { isWorking = false }
        do {
            let projectKey = String(issue.key.split(separator: "-").dropLast().joined(separator: "-"))
            let authoring = JiraAuthoringFactory.make()
            guard let type = try await authoring.issueTypes(projectKey: projectKey).first(where: \.isSubtask) else {
                errorMessage = "This project has no subtask type."
                return
            }
            _ = try await authoring.create(JiraNewIssue(projectKey: projectKey, issueTypeID: type.id,
                                                       summary: title, parentKey: issue.key))
            subtaskTitle = ""
            errorMessage = nil
            issue = try await jiraViewModel.fetchIssue(key: issue.key)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Linked issues").font(.headline)

            ForEach(issue.links ?? []) { link in
                HStack {
                    refRow(link.issue, prefix: link.label)
                    Button {
                        Task { await jiraViewModel.unlink(issue, link) ; await refresh() }
                    } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("Remove link")
                    .disabled(link.id.hasPrefix(JiraComment.pendingPrefix))
                }
            }

            HStack {
                Picker("", selection: $choice) {
                    Text("Link as…").tag(LinkChoice?.none)
                    ForEach(choices) { Text($0.label).tag(Optional($0)) }
                }
                .labelsHidden()
                .fixedSize()

                TextField("PROJ-123", text: $linkKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await addLink() } }

                Button("Link") { Task { await addLink() } }
                    .disabled(choice == nil || linkKey.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
        }
    }

    private func addLink() async {
        guard let choice else { return }
        let key = linkKey.trimmingCharacters(in: .whitespaces).uppercased()
        guard !key.isEmpty, key != issue.key else { return }

        isWorking = true
        defer { isWorking = false }
        if await jiraViewModel.link(issue, choice.type, direction: choice.direction, to: key) {
            linkKey = ""
            errorMessage = nil
            await refresh()
        } else {
            errorMessage = jiraViewModel.actionMessage
        }
    }

    /// The board's copy was patched with a placeholder; the real links come
    /// from Jira.
    private func refresh() async {
        if let fresh = try? await jiraViewModel.fetchIssue(key: issue.key) {
            issue.links = fresh.links
            issue.subtasks = fresh.subtasks
        }
    }

    private func refRow(_ ref: JiraIssueRef, prefix: String?) -> some View {
        HStack(spacing: 6) {
            if let prefix { Text(prefix).foregroundStyle(.secondary) }
            Text(ref.key).fontDesign(.monospaced)
            Text(ref.summary).lineLimit(1)
            Spacer()
            if !ref.status.isEmpty {
                Text(ref.status)
                    .font(.callout)
                    .padding(.horizontal, 6)
                    .background(.quaternary, in: Capsule())
            }
        }
        .font(.callout)
    }
}
