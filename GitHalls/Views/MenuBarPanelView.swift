//
//  MenuBarPanelView.swift
//  GitHalls
//

import SwiftUI
import AppKit

struct MenuBarPanelView: View {
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if viewModel.repositoryURL != nil {
                changesSection
                Divider()
            }
            if !viewModel.recentRepositoryURLs.isEmpty {
                recentsSection
                Divider()
            }
            footer
        }
        .frame(width: 280)
        .task {
            await viewModel.refreshStatus()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let repoURL = viewModel.repositoryURL {
                Text(repoURL.lastPathComponent)
                    .font(.headline)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(viewModel.currentBranch ?? "—")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Text("No Repository Open")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.changes.isEmpty {
                Label("No changes", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Text("\(viewModel.changes.count) changed file\(viewModel.changes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.changes.prefix(5)) { change in
                    HStack(spacing: 6) {
                        StatusBadge(status: change.status)
                        Text(change.fileName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                if viewModel.changes.count > 5 {
                    Text("+ \(viewModel.changes.count - 5) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.syncAhead > 0 || viewModel.syncBehind > 0 {
                HStack(spacing: 10) {
                    if viewModel.syncAhead > 0 {
                        Label("\(viewModel.syncAhead)", systemImage: "arrow.up")
                    }
                    if viewModel.syncBehind > 0 {
                        Label("\(viewModel.syncBehind)", systemImage: "arrow.down")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RECENT")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            ForEach(viewModel.recentRepositoryURLs.prefix(3), id: \.self) { url in
                Button {
                    viewModel.open(url)
                    bringMainWindowToFront()
                } label: {
                    Label(url.lastPathComponent, systemImage: "clock")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button("Open GitHalls") {
                bringMainWindowToFront()
            }
            Spacer()
            Button {
                Task { await viewModel.fetch() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
    }

    private func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
