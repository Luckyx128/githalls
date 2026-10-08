//
//  KanbanColumnView.swift
//  GitHalls
//

import SwiftUI

/// One status column: a header, then its cards, scrolling on their own. The
/// header is the handle for reordering columns; the body takes dropped cards.
struct KanbanColumnView: View {
    let column: JiraIssueGroup
    @Bindable var viewModel: JiraViewModel
    let board: KanbanBoardModel
    let isCollapsed: Bool
    let onOpen: (JiraIssue) -> Void

    @State private var targetedCard: String?
    @State private var isTargeted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: KanbanMotion { KanbanMotion(reduced: reduceMotion) }

    var body: some View {
        Group {
            if isCollapsed { collapsedBody } else { expandedBody }
        }
        .background(Color.gray.opacity(isTargeted ? 0.12 : 0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTargeted ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isTargeted ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(motion.spring, value: isTargeted)
        .dropDestination(for: KanbanDragItem.self) { items, _ in
            drop(items, beforeCard: nil)
        } isTargeted: { isTargeted = $0 }
        .contextMenu { columnMenu }
    }

    // MARK: - Expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(column.issues) { issue in
                        if targetedCard == issue.key { placeholder }

                        KanbanCardView(
                            issue: issue,
                            viewModel: viewModel,
                            neighbours: neighbours,
                            shakeCount: board.shakes[issue.key] ?? 0,
                            onOpen: { onOpen(issue) },
                            onMove: { board.drop(cardKey: issue.key, onto: $0) }
                        )
                        .dropDestination(for: KanbanDragItem.self) { items, _ in
                            drop(items, beforeCard: issue.key)
                        } isTargeted: { targeted in
                            if targeted {
                                targetedCard = issue.key
                            } else if targetedCard == issue.key {
                                targetedCard = nil
                            }
                        }
                    }

                    if column.issues.isEmpty {
                        Text("Nothing here")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(8)
                .animation(motion.spring, value: targetedCard)
                .animation(motion.spring, value: column.issues.map(\.key))
            }
        }
        .frame(width: 280)
    }

    /// The gap a card will land in.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .frame(height: 44)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Self.color(for: column.category))
                .frame(width: 8, height: 8)
            Text(column.status)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            countBadge

            Button {
                board.toggleCollapsed(column.status)
            } label: {
                Image(systemName: "chevron.left.to.line")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Collapse column")
            .accessibilityLabel("Collapse \(column.status)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .draggable(KanbanDragItem.column(status: column.status)) {
            Text(column.status)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                .shadow(radius: 8, y: 4)
        }
        .help("Drag to reorder columns")
    }

    /// The count is the WIP figure: how much is in flight in this status.
    private var countBadge: some View {
        Text("\(column.count)")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .contentTransition(.numericText())
            .animation(motion.spring, value: column.count)
            .accessibilityLabel("\(column.count) issues")
    }

    // MARK: - Collapsed

    private var collapsedBody: some View {
        Button {
            board.toggleCollapsed(column.status)
        } label: {
            VStack(spacing: 10) {
                Circle()
                    .fill(Self.color(for: column.category))
                    .frame(width: 8, height: 8)
                countBadge
                Text(column.status)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: max(60, CGFloat(column.status.count) * 8))
            }
            .padding(.vertical, 10)
            .frame(width: 40)
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Expand \(column.status)")
        .accessibilityLabel("Expand \(column.status), \(column.count) issues")
    }

    // MARK: - Drops and menus

    /// Cards and columns both land on a column; which one it was decides what
    /// happens. The card goes to this status, wherever in the column it was
    /// dropped — ranking inside a column is Jira's, not ours, until it is wired.
    private func drop(_ items: [KanbanDragItem], beforeCard: String?) -> Bool {
        targetedCard = nil

        guard let item = items.first else { return false }

        switch item {
        case .card(let key):
            return board.drop(cardKey: key, onto: column.status)
        case .column(let status):
            board.moveColumn(status, onto: column.status)
            return true
        }
    }

    /// The columns either side, so a card can be moved without a pointer.
    private var neighbours: [String] {
        let all = board.visibleColumns.map(\.status)
        guard let index = all.firstIndex(of: column.status) else { return [] }

        return [index - 1, index + 1].filter(all.indices.contains).map { all[$0] }
    }

    @ViewBuilder
    private var columnMenu: some View {
        Button(isCollapsed ? "Expand Column" : "Collapse Column") { board.toggleCollapsed(column.status) }
        Button("Hide Column") { board.toggleHidden(column.status) }

        Divider()

        Button("Move Column Left") { board.shiftColumn(column.status, by: -1) }
        Button("Move Column Right") { board.shiftColumn(column.status, by: 1) }
    }

    /// Jira's three categories, in the colours the app already uses for state.
    static func color(for category: String) -> Color {
        switch category {
        case "done": .green
        case "indeterminate": .blue
        default: .secondary
        }
    }
}
