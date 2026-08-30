//
//  KanbanSidebarView.swift
//  GitHalls
//

import SwiftUI

struct KanbanSidebarView: View {
    @Bindable var viewModel: JiraViewModel
    @State private var expandedOverride: [String: Bool] = [:]

    private func isExpanded(_ group: JiraViewModel.IssueGroup) -> Binding<Bool> {
        Binding(
            get: { expandedOverride[group.status] ?? (group.category != "done") },
            set: { expandedOverride[group.status] = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("JQL", text: $viewModel.jql)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.refresh() } }
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isLoading)
            }
            .padding(8)

            Divider()

            Group {
                if !viewModel.isConfigured {
                    ContentUnavailableView(
                        "Jira Not Connected",
                        systemImage: "link.badge.plus",
                        description: Text("Open Settings (⌘,) to connect your Jira account.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.issues.isEmpty {
                    ContentUnavailableView("No Issues", systemImage: "tray")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $viewModel.selectedIssueID) {
                        ForEach(viewModel.issuesByStatus) { group in
                            DisclosureGroup(isExpanded: isExpanded(group)) {
                                ForEach(group.issues) { issue in
                                    IssueRow(issue: issue)
                                        .tag(issue.id)
                                }
                            } label: {
                                HStack {
                                    Text(group.status)
                                    Spacer()
                                    Text("\(group.issues.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
        }
        .task(id: viewModel.isConfigured) {
            if viewModel.isConfigured {
                await viewModel.refresh()
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct IssueRow: View {
    let issue: JiraIssue

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(issue.key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(issue.summary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch issue.statusCategory {
        case "done": .green
        case "indeterminate": .blue
        default: .secondary
        }
    }
}
