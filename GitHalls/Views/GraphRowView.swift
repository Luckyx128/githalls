//
//  GraphRowView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import SwiftUI

enum GraphMetrics {
    static let rowHeight: CGFloat = 28
    static let laneWidth: CGFloat = 14
    static let laneInset: CGFloat = 8
    static let nodeRadius: CGFloat = 4
    static let lineWidth: CGFloat = 1.5

    /// A repository with forty concurrent branches must not get a gutter that
    /// eats the window. The rightmost lanes clip instead.
    static let maxGutterWidth: CGFloat = 220

    static func gutterWidth(laneCount: Int) -> CGFloat {
        min(laneInset * 2 + laneWidth * CGFloat(max(laneCount, 1)), maxGutterWidth)
    }

    static func x(lane: Int) -> CGFloat {
        laneInset + laneWidth * (CGFloat(lane) + 0.5)
    }
}

struct GraphRowView: View {
    let row: GraphRow
    let gutterWidth: CGFloat
    let isHead: Bool

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            GraphLaneCanvas(row: row, isHead: isHead)
                .frame(width: gutterWidth)

            if !row.commit.refs.isEmpty {
                GraphRefChips(refs: row.commit.refs)
            }

            Text(row.commit.summary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(row.commit.authorName)
                .lineLimit(1)
                .frame(width: 120, alignment: .trailing)

            Text(Self.dateFormatter.string(from: row.commit.date))
                .frame(width: 80, alignment: .trailing)

            Text(row.commit.shortHash)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 64, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .padding(.trailing, 8)
        .frame(height: GraphMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}

/// The gutter for one row.
///
/// Everything it draws comes from `row.edges`, which already spans the full
/// height of the band, so consecutive rows tile into continuous lines — as long
/// as the list gives every row the same height and no spacing between them.
private struct GraphLaneCanvas: View {
    let row: GraphRow
    let isHead: Bool

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2

            // Pass-throughs first, so a node always sits on top of the lines
            // crossing behind it.
            for edge in row.edges where edge.kind == .passThrough {
                stroke(&context, edge: edge, height: size.height, mid: mid)
            }
            for edge in row.edges where edge.kind != .passThrough {
                stroke(&context, edge: edge, height: size.height, mid: mid)
            }

            let centre = CGPoint(x: GraphMetrics.x(lane: row.lane), y: mid)
            let radius = GraphMetrics.nodeRadius
            let node = Path(ellipseIn: CGRect(
                x: centre.x - radius, y: centre.y - radius,
                width: radius * 2, height: radius * 2
            ))
            let color = GraphLanePalette.color(forLane: row.lane)

            if isHead {
                // A halo in the row's own background, so the ring below reads as
                // a ring rather than merging into whatever line passes behind.
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: centre.x - radius - 3, y: centre.y - radius - 3,
                        width: (radius + 3) * 2, height: (radius + 3) * 2
                    )),
                    with: .color(color.opacity(0.35)),
                    lineWidth: 2
                )
            }

            if row.commit.isMerge {
                // Hollow: a merge is where lines meet, not where work landed.
                context.fill(node, with: .color(.white.opacity(0.001)))
                context.stroke(node, with: .color(color), lineWidth: 2)
            } else {
                context.fill(node, with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }

    private func stroke(_ context: inout GraphicsContext, edge: GraphEdge, height: CGFloat, mid: CGFloat) {
        let x0 = GraphMetrics.x(lane: edge.from)
        let x1 = GraphMetrics.x(lane: edge.to)
        var path = Path()

        switch edge.kind {
        case .passThrough:
            path.move(to: CGPoint(x: x0, y: 0))
            path.addLine(to: CGPoint(x: x0, y: height))
        case .incoming:
            path.move(to: CGPoint(x: x0, y: 0))
            if x0 == x1 {
                path.addLine(to: CGPoint(x: x1, y: mid))
            } else {
                path.addCurve(
                    to: CGPoint(x: x1, y: mid),
                    control1: CGPoint(x: x0, y: mid * 0.6),
                    control2: CGPoint(x: x1, y: mid * 0.7)
                )
            }
        case .outgoing:
            path.move(to: CGPoint(x: x0, y: mid))
            if x0 == x1 {
                path.addLine(to: CGPoint(x: x1, y: height))
            } else {
                path.addCurve(
                    to: CGPoint(x: x1, y: height),
                    control1: CGPoint(x: x0, y: mid * 1.4),
                    control2: CGPoint(x: x1, y: mid * 1.3)
                )
            }
        }

        context.stroke(
            path,
            with: .color(GraphLanePalette.color(forLane: edge.colorLane)),
            style: StrokeStyle(lineWidth: GraphMetrics.lineWidth, lineCap: .round)
        )
    }
}

/// The refs pointing at a commit. Capped, because a commit carrying eight of
/// them would otherwise squeeze the summary to nothing.
private struct GraphRefChips: View {
    let refs: [GitRef]

    private static let visibleLimit = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(refs.prefix(Self.visibleLimit)) { ref in
                chip(for: ref)
            }
            if refs.count > Self.visibleLimit {
                Text("+\(refs.count - Self.visibleLimit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .help(refs.map(\.name).joined(separator: ", "))
    }

    @ViewBuilder
    private func chip(for ref: GitRef) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol(for: ref.kind))
            Text(ref.name)
                .lineLimit(1)
        }
        .font(.caption2)
        .fontWeight(ref.kind == .head ? .semibold : .regular)
        .foregroundStyle(foreground(for: ref.kind))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background(for: ref.kind), in: Capsule())
    }

    private func symbol(for kind: GitRef.Kind) -> String {
        switch kind {
        case .head: "arrowtriangle.right.fill"
        case .localBranch: "arrow.triangle.branch"
        case .remoteBranch: "cloud"
        case .tag: "tag"
        }
    }

    private func foreground(for kind: GitRef.Kind) -> Color {
        switch kind {
        case .head: .white
        case .localBranch: .accentColor
        case .remoteBranch: .secondary
        case .tag: .yellow
        }
    }

    private func background(for kind: GitRef.Kind) -> AnyShapeStyle {
        switch kind {
        case .head: AnyShapeStyle(Color.accentColor)
        case .localBranch: AnyShapeStyle(Color.accentColor.opacity(0.18))
        case .remoteBranch: AnyShapeStyle(.quaternary)
        case .tag: AnyShapeStyle(Color.yellow.opacity(0.20))
        }
    }
}
