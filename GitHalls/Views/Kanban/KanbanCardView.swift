//
//  KanbanCardView.swift
//  GitHalls
//

import SwiftUI

/// KEY · type · priority, the title, and who has it. Click opens it, right-click
/// moves it, and a drag onto another column moves it too.
struct KanbanCardView: View {
    let issue: JiraIssue
    @Bindable var viewModel: JiraViewModel

    /// Columns on either side, for the accessibility moves.
    let neighbours: [String]
    let shakeCount: Int
    let onOpen: () -> Void
    let onMove: (String) -> Void

    /// Cancelled when the pointer leaves, so crossing the board asks Jira nothing.
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isBusy: Bool { viewModel.busyIssues.contains(issue.key) }
    private var motion: KanbanMotion { KanbanMotion(reduced: reduceMotion) }

    var body: some View {
        Button(action: onOpen) { content }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("\(issue.key) — \(issue.summary)")
            .opacity(isBusy ? 0.5 : 1)
            .disabled(isBusy)
            .scaleEffect(isHovering && !isBusy ? 1.015 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0.06), radius: isHovering ? 6 : 1.5, y: isHovering ? 3 : 1)
            .animation(motion.spring, value: isHovering)
            .modifier(KanbanShake(count: CGFloat(shakeCount)))
            .animation(motion.shake, value: shakeCount)
            .draggable(KanbanDragItem.card(key: issue.key)) {
                content
                    .frame(width: 264)
                    .scaleEffect(1.04)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
            }
            .onHover { hovering in
                isHovering = hovering
                prefetchOnRest(hovering)
            }
            .contextMenu { menu }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Drag to another column to move it")
            .accessibilityActions {
                ForEach(neighbours, id: \.self) { status in
                    Button("Move to \(status)") { onMove(status) }
                }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(issue.summary)
                .font(.rowPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(metaLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let assignee = issue.assigneeName {
                Text(assignee)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }

    /// A right-click has to be instant, and a macOS menu cannot be filled in
    /// after it opens — so the moves are fetched while the pointer rests on the
    /// card, which is what always precedes the right-click. One request per card
    /// actually pointed at, and the cache makes a second look free.
    private func prefetchOnRest(_ hovering: Bool) {
        hoverTask?.cancel()

        guard hovering else {
            hoverTask = nil
            return
        }

        hoverTask = Task {
            // A pointer crossing the board is not a request for anything.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            await viewModel.prefetchTransitions(for: issue)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open Issue", action: onOpen)

        if let transitions = viewModel.cachedTransitions(for: issue) {
            if transitions.isEmpty {
                Button("No moves available") {}.disabled(true)
            } else {
                ForEach(transitions) { transition in
                    Button(moveTitle(transition, among: transitions)) {
                        Task { await viewModel.move(issue, to: transition) }
                    }
                }
            }
        } else {
            Button("Loading moves…") {}.disabled(true)
        }

        if let mine = viewModel.myAccountID, issue.assigneeAccountID == mine {
            Button("Assigned to you") {}.disabled(true)
        } else {
            Button("Assign to me") {
                Task { await viewModel.assignToMe(issue) }
            }
        }
    }

    /// The ellipsis is Jira's own convention for "this one asks for more".
    private func moveTitle(_ transition: JiraTransition, among all: [JiraTransition]) -> String {
        "Move to " + JiraWorkflow.label(for: transition, among: all) + (transition.hasScreen ? "…" : "")
    }

    /// The key first, since it is what people say out loud.
    private var metaLine: String {
        [issue.key, issue.type, issue.priority].compactMap { $0 }.joined(separator: " · ")
    }
}
