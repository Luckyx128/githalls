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

    /// How many columns the gutter ever draws.
    ///
    /// A repository with dozens of concurrent branches would otherwise push the
    /// summary off the row — and, worse, draw its outer lanes at an x the gutter
    /// never reserved, straight through the commit text.
    static let maxDrawnLanes = 8

    /// The strip past the last drawn column where everything further out is
    /// collapsed onto one marker.
    static let overflowWidth: CGFloat = 14

    static func drawnLaneCount(_ laneCount: Int) -> Int {
        min(max(laneCount, 1), maxDrawnLanes)
    }

    static func hasOverflow(laneCount: Int) -> Bool {
        laneCount > maxDrawnLanes
    }

    static func gutterWidth(laneCount: Int) -> CGFloat {
        laneInset * 2
            + laneWidth * CGFloat(drawnLaneCount(laneCount))
            + (hasOverflow(laneCount: laneCount) ? overflowWidth : 0)
    }

    static func x(lane: Int) -> CGFloat {
        laneInset + laneWidth * (CGFloat(lane) + 0.5)
    }

    static func isDrawn(lane: Int) -> Bool { lane < maxDrawnLanes }

    /// Where a line heading for a column the gutter does not draw leaves.
    static func overflowX(laneCount: Int) -> CGFloat {
        laneInset + laneWidth * CGFloat(drawnLaneCount(laneCount)) + overflowWidth / 2
    }
}

struct GraphRowView: View {
    let row: GraphRow
    let laneCount: Int
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
            GraphLaneCanvas(row: row, laneCount: laneCount, isHead: isHead)
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
struct GraphLaneCanvas: View {
    let row: GraphRow
    let laneCount: Int
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

            drawNode(&context, mid: mid)
        }
        // Belt and braces: the lane cap already keeps every coordinate inside,
        // and this guarantees nothing can reach the commit text if it does not.
        .clipped()
        .allowsHitTesting(false)
    }

    private func drawNode(_ context: inout GraphicsContext, mid: CGFloat) {
        let color = GraphLanePalette.color(forLane: row.lane)
        let radius = GraphMetrics.nodeRadius

        guard GraphMetrics.isDrawn(lane: row.lane) else {
            // The commit lives in a column the gutter does not draw. It still
            // has a row — only its position in the graph is off to the right.
            let centre = CGPoint(x: GraphMetrics.overflowX(laneCount: laneCount), y: mid)
            let dot = Path(ellipseIn: CGRect(
                x: centre.x - 2.5, y: centre.y - 2.5, width: 5, height: 5
            ))
            context.fill(dot, with: .color(color.opacity(0.75)))
            return
        }

        let centre = CGPoint(x: GraphMetrics.x(lane: row.lane), y: mid)
        let node = Path(ellipseIn: CGRect(
            x: centre.x - radius, y: centre.y - radius,
            width: radius * 2, height: radius * 2
        ))

        if isHead {
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
            context.stroke(node, with: .color(color), lineWidth: 2)
        } else {
            context.fill(node, with: .color(color))
        }
    }

    private func stroke(_ context: inout GraphicsContext, edge: GraphEdge, height: CGFloat, mid: CGFloat) {
        let fromDrawn = GraphMetrics.isDrawn(lane: edge.from)
        let toDrawn = GraphMetrics.isDrawn(lane: edge.to)
        // Both ends are past the cap: nothing meaningful to show, and drawing it
        // would just pile lines on the overflow marker.
        guard fromDrawn || toDrawn else { return }

        let overflowX = GraphMetrics.overflowX(laneCount: laneCount)
        let x0 = fromDrawn ? GraphMetrics.x(lane: edge.from) : overflowX
        let x1 = toDrawn ? GraphMetrics.x(lane: edge.to) : overflowX
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

        let color = GraphLanePalette.color(forLane: edge.colorLane)
        context.stroke(
            path,
            with: .color(fromDrawn && toDrawn ? color : color.opacity(0.45)),
            style: StrokeStyle(lineWidth: GraphMetrics.lineWidth, lineCap: .round)
        )
    }
}

/// The gutter of an expanded detail block.
///
/// An expanded row breaks the list's run of equal-height bands, so the lane
/// lines would stop dead at the top of the detail and start again below it.
/// Continuing them here keeps the graph readable while a commit is open.
struct GraphLaneContinuation: View {
    /// The edges leaving the bottom of the row above.
    let edges: [GraphEdge]
    let laneCount: Int

    var body: some View {
        Canvas { context, size in
            for edge in edges {
                guard GraphMetrics.isDrawn(lane: edge.to) else { continue }
                let x = GraphMetrics.x(lane: edge.to)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(GraphLanePalette.color(forLane: edge.colorLane).opacity(0.5)),
                    style: StrokeStyle(lineWidth: GraphMetrics.lineWidth, lineCap: .butt)
                )
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
