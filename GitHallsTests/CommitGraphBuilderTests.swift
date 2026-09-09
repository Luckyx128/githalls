//
//  CommitGraphBuilderTests.swift
//  GitHallsTests
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import Testing
@testable import GitHalls

struct CommitGraphBuilderTests {

    /// A commit with only the two things the builder reads: its hash and its
    /// parents. Everything else is filler.
    private func c(_ hash: String, _ parents: String...) -> GraphCommit {
        GraphCommit(
            commit: Commit(
                hash: hash,
                shortHash: String(hash.prefix(7)),
                authorName: "Ada",
                date: Date(timeIntervalSince1970: 0),
                summary: hash
            ),
            parents: parents,
            refs: [],
            committerDate: Date(timeIntervalSince1970: 0)
        )
    }

    private func row(_ graph: CommitGraph, _ hash: String) -> GraphRow {
        graph.rows.first { $0.commit.hash == hash }!
    }

    private func passThroughLanes(_ row: GraphRow) -> Set<Int> {
        Set(row.edges.filter { $0.kind == .passThrough }.map(\.from))
    }

    // MARK: - Shape

    @Test func linearHistory() {
        let graph = CommitGraphBuilder.build([c("c", "b"), c("b", "a"), c("a")])

        #expect(graph.laneCount == 1)
        #expect(graph.rows.allSatisfy { $0.lane == 0 })
        #expect(graph.rows.allSatisfy { passThroughLanes($0).isEmpty })
        // The root stops: nothing leaves the bottom of the last row.
        #expect(row(graph, "a").edges.contains { $0.kind == .outgoing } == false)
    }

    @Test func forkIntoTwoTips() {
        let graph = CommitGraphBuilder.build([c("t1", "base"), c("t2", "base"), c("base")])

        #expect(row(graph, "t1").lane == 0)
        #expect(row(graph, "t2").lane == 1)

        // Both lines converge on the shared parent.
        let base = row(graph, "base")
        #expect(base.lane == 0)
        #expect(base.edges.filter { $0.kind == .incoming }.count == 2)
        #expect(Set(base.edges.filter { $0.kind == .incoming }.map(\.from)) == [0, 1])
    }

    @Test func twoParentMerge() {
        let graph = CommitGraphBuilder.build([c("m", "a", "b"), c("a", "r"), c("b", "r"), c("r")])

        let merge = row(graph, "m")
        let outgoing = merge.edges.filter { $0.kind == .outgoing }
        #expect(outgoing.count == 2)
        #expect(outgoing[0].to == merge.lane)      // first parent stays put
        #expect(outgoing[1].to != merge.lane)      // second forks a new column
        #expect(graph.laneCount == 2)
        #expect(row(graph, "r").edges.filter { $0.kind == .incoming }.count == 2)
    }

    @Test func octopusMerge() {
        let graph = CommitGraphBuilder.build([c("m", "a", "b", "c"), c("a"), c("b"), c("c")])

        #expect(row(graph, "m").edges.filter { $0.kind == .outgoing }.count == 3)
        #expect(graph.laneCount == 3)
    }

    @Test func mergeRejoiningALiveLane() {
        // lane 0 is already heading for "b" when the merge asks for it, so the
        // second parent rejoins rather than opening a third column.
        let graph = CommitGraphBuilder.build([c("t1", "b"), c("m", "a", "b"), c("a", "b"), c("b")])

        #expect(graph.laneCount == 2)
        let merge = row(graph, "m")
        #expect(merge.edges.filter { $0.kind == .outgoing }.map(\.to).contains(0))
    }

    @Test func orphanBranchNeverConverges() {
        let graph = CommitGraphBuilder.build([c("a1", "a2"), c("b1", "b2"), c("a2"), c("b2")])

        #expect(graph.laneCount == 2)
        #expect(row(graph, "a1").lane == 0)
        #expect(row(graph, "b1").lane == 1)
        // No row ever takes two arrivals: the histories never touch.
        #expect(graph.rows.allSatisfy { $0.edges.filter { $0.kind == .incoming }.count <= 1 })
    }

    // MARK: - Edges across distance

    @Test func longDistanceEdgeCrossesEveryRowBetween() {
        // m merges "z", which sits ten rows further down.
        var commits = [c("m", "a", "z"), c("a", "x1")]
        for index in 1...8 {
            commits.append(c("x\(index)", "x\(index + 1)"))
        }
        commits.append(c("x9", "z"))
        commits.append(c("z"))

        let graph = CommitGraphBuilder.build(commits)
        let zLane = row(graph, "m").edges.filter { $0.kind == .outgoing }.last!.to

        // The fork row itself draws the departure, not a pass-through...
        #expect(passThroughLanes(row(graph, "m")).contains(zLane) == false)
        // ...the ten rows in between carry it...
        let crossing = graph.rows.filter { passThroughLanes($0).contains(zLane) }
        #expect(crossing.count == 10)
        #expect(crossing.contains { $0.commit.hash == "a" })
        #expect(crossing.contains { $0.commit.hash == "x9" })
        // ...and the destination row receives it instead of passing it on.
        #expect(passThroughLanes(row(graph, "z")).contains(zLane) == false)
        #expect(row(graph, "z").edges.filter { $0.kind == .incoming }.count == 2)
    }

    /// --max-count cuts the history off mid-graph. The lane stays occupied and
    /// its line runs off the bottom edge, which is the honest answer.
    @Test func parentOutsideTheWindow() {
        let graph = CommitGraphBuilder.build([c("m", "a", "b"), c("a", "gone")])

        #expect(graph.laneCount == 2)
        let last = graph.rows.last!
        #expect(last.commit.hash == "a")
        #expect(passThroughLanes(last).contains(1))
        #expect(last.edges.contains { $0.kind == .outgoing })
    }

    @Test func freedLaneIsReusedRatherThanAppended() {
        // lane 1 is freed when p absorbs both tips, then handed to t3.
        let graph = CommitGraphBuilder.build([c("t1", "p"), c("t2", "p"), c("p", "q"), c("t3", "q"), c("q")])

        #expect(row(graph, "t2").lane == 1)
        #expect(row(graph, "t3").lane == 1)  // reused, not lane 2
        #expect(graph.laneCount == 2)
    }

    // MARK: - Invariants

    /// The strongest single assertion here: whatever leaves the bottom of a row
    /// enters the top of the next one. That is literally "the lines connect",
    /// and it catches any future edge-emission bug in one place.
    @Test func edgesTileVertically() {
        let graphs = [
            CommitGraphBuilder.build([c("c", "b"), c("b", "a"), c("a")]),
            CommitGraphBuilder.build([c("m", "a", "b"), c("a", "r"), c("b", "r"), c("r")]),
            CommitGraphBuilder.build([c("m", "a", "b", "c"), c("a"), c("b"), c("c")]),
            CommitGraphBuilder.build([c("t1", "p"), c("t2", "p"), c("p", "q"), c("t3", "q"), c("q")]),
            CommitGraphBuilder.build([c("a1", "a2"), c("b1", "b2"), c("a2"), c("b2")]),
        ]

        for graph in graphs {
            for (upper, lower) in zip(graph.rows, graph.rows.dropFirst()) {
                let leaving = Set(upper.edges.compactMap { edge -> Int? in
                    switch edge.kind {
                    case .outgoing, .passThrough: return edge.to
                    case .incoming: return nil
                    }
                })
                let entering = Set(lower.edges.compactMap { edge -> Int? in
                    switch edge.kind {
                    case .incoming, .passThrough: return edge.from
                    case .outgoing: return nil
                    }
                })
                #expect(leaving == entering, "\(upper.commit.hash) → \(lower.commit.hash)")
            }
        }
    }

    @Test func buildIsDeterministic() {
        let commits = [c("m", "a", "b"), c("a", "r"), c("b", "r"), c("r")]

        #expect(CommitGraphBuilder.build(commits) == CommitGraphBuilder.build(commits))
    }

    @Test func emptyInput() {
        let graph = CommitGraphBuilder.build([])

        #expect(graph.rows.isEmpty)
        #expect(graph.laneCount == 1)  // never 0: the view divides by it
    }
}
