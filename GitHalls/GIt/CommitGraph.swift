//
//  CommitGraph.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation

struct CommitGraph: Equatable {
    let rows: [GraphRow]

    /// Every row draws its gutter this wide, so the text columns line up down
    /// the whole list. Never zero — the view divides by it.
    let laneCount: Int

    static let empty = CommitGraph(rows: [], laneCount: 1)
}

struct GraphRow: Identifiable, Equatable {
    let commit: GraphCommit

    /// The column the node sits in.
    let lane: Int

    let edges: [GraphEdge]

    var id: String { commit.hash }

    /// The edges that leave the bottom of this row — everything the next row
    /// receives at its top. An expanded detail block draws these to keep the
    /// lane lines running through it.
    var continuingEdges: [GraphEdge] {
        edges.filter { $0.kind != .incoming }
    }
}

/// One segment inside a single row's vertical band.
///
/// A row is drawn entirely from its own edges: `incoming` runs from the top
/// boundary to the node, `outgoing` from the node to the bottom boundary, and
/// `passThrough` crosses top to bottom without touching the node. Because every
/// row emits a segment for every occupied column, consecutive rows tile
/// seamlessly and a long-distance edge is just a run of `passThrough`s — no view
/// ever has to look at the row above or below it.
struct GraphEdge: Hashable {
    enum Kind: Hashable {
        case incoming
        case outgoing
        case passThrough
    }

    let from: Int
    let to: Int
    let kind: Kind

    /// Which lane's colour the segment takes. Not always `from`: a line keeps
    /// its identity through a merge by colouring arrivals from their source and
    /// departures from their destination.
    let colorLane: Int
}
