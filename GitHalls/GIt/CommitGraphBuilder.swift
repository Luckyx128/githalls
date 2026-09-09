//
//  CommitGraphBuilder.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation

/// Turns a topologically ordered commit list into drawable rows.
///
/// The state is one array of active lanes, where `lanes[column]` is the hash
/// that column is currently waiting for. Because the input is `--topo-order`,
/// every commit is already expected by the time it is reached, unless it is a
/// branch tip — which is what lets the whole thing be a single forward pass with
/// no lookahead and no upward edges.
///
/// Three rules keep the output deterministic, and every one of them is load
/// bearing:
///
/// 1. Never iterate a `Set` or `Dictionary` to produce output order. Every loop
///    below walks `lanes` by index or `parents` in git's own order.
/// 2. Leftmost-first everywhere — `arriving.first`, `firstIndex`, `claimFreeLane`.
/// 3. Lanes are never compacted or shifted. A column's index is fixed for its
///    whole life, which is what makes a pass-through an exact vertical line and
///    keeps the gutter width constant across the list.
///
/// Together with a fixed ref set they mean adding one commit at the top does not
/// reshuffle the columns beneath it, so the graph does not jump on refresh.
enum CommitGraphBuilder {
    static func build(_ commits: [GraphCommit]) -> CommitGraph {
        guard !commits.isEmpty else { return .empty }

        var lanes: [String?] = []
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)
        var maxLaneCount = 1

        for commit in commits {
            let hash = commit.hash

            // 1. Every column waiting for this commit, in index order.
            let arriving = lanes.indices.filter { lanes[$0] == hash }

            // 2. The node's column. A tip nobody waits for opens a fresh one.
            let lane = arriving.first ?? claimFreeLane(&lanes)

            var edges: [GraphEdge] = []

            // 3. Every arrival bends into the node, keeping its own colour, so a
            //    branch reads as one continuous line right up to the merge that
            //    ends it.
            for index in arriving {
                edges.append(GraphEdge(from: index, to: lane, kind: .incoming, colorLane: index))
            }

            // 4. Columns this row does not touch run straight through it.
            for index in lanes.indices where lanes[index] != nil && !arriving.contains(index) {
                edges.append(GraphEdge(from: index, to: index, kind: .passThrough, colorLane: index))
            }

            // 5. Arrivals that did not become the node's column are spent. Freed
            //    before the parent lookup below, so a column released here is
            //    never mistaken for one already holding a parent.
            for index in arriving where index != lane {
                lanes[index] = nil
            }

            // 6. Outgoing. The first parent keeps the node's column — that is
            //    what makes a branch a straight line instead of a zigzag.
            if commit.parents.isEmpty {
                lanes[lane] = nil  // root commit: the line stops here
            } else {
                lanes[lane] = commit.parents[0]
                edges.append(GraphEdge(from: lane, to: lane, kind: .outgoing, colorLane: lane))

                for parent in commit.parents.dropFirst() {  // merge, octopus
                    let target: Int
                    if let existing = lanes.firstIndex(where: { $0 == parent }) {
                        target = existing  // rejoins a column already heading there
                    } else {
                        target = claimFreeLane(&lanes)
                        lanes[target] = parent  // forks a new one
                    }
                    // Coloured by the destination: the merged-in side starts
                    // wearing its own colour immediately below the merge node.
                    edges.append(GraphEdge(from: lane, to: target, kind: .outgoing, colorLane: target))
                }
            }

            maxLaneCount = max(maxLaneCount, lanes.count)
            rows.append(GraphRow(commit: commit, lane: lane, edges: edges))
        }

        return CommitGraph(rows: rows, laneCount: maxLaneCount)
    }

    /// The leftmost free column, appending only when they are all taken. Leftmost
    /// rather than always-append is what stops the graph growing one column for
    /// every branch that has ever existed.
    private static func claimFreeLane(_ lanes: inout [String?]) -> Int {
        if let free = lanes.firstIndex(where: { $0 == nil }) { return free }
        lanes.append(nil)
        return lanes.count - 1
    }
}
