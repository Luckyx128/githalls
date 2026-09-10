//
//  MergeStateParserTests.swift
//  GitHallsTests
//

import Foundation
import Testing
@testable import GitHalls

struct MergeStateParserTests {

    @Test func unmergedPathsCollapsesStages() {
        let raw = """
        100644 a1b2c3d4 1\tGitHalls/ContentView.swift
        100644 e5f6a7b8 2\tGitHalls/ContentView.swift
        100644 c9d0e1f2 3\tGitHalls/ContentView.swift
        100644 33445566 2\tREADME.md

        """

        #expect(MergeStateParser.unmergedPaths(raw) == ["GitHalls/ContentView.swift", "README.md"])
    }

    @Test func unmergedPathsEmptyWhenNothingConflicts() {
        #expect(MergeStateParser.unmergedPaths("").isEmpty)
    }

    @Test func unmergedPathsKeepsSpaces() {
        let raw = "100644 a1b2c3d4 1\tDocs/Release Notes.md\n"

        #expect(MergeStateParser.unmergedPaths(raw) == ["Docs/Release Notes.md"])
    }

    @Test func conflictMarkerPathsIgnoresWhitespaceWarnings() {
        let raw = """
        GitHalls/ContentView.swift:14: leftover conflict marker
        GitHalls/ContentView.swift:18: leftover conflict marker
        README.md:3: trailing whitespace.
        GitHalls/GIt/GitService.swift:7: leftover conflict marker

        """

        #expect(MergeStateParser.conflictMarkerPaths(raw) == [
            "GitHalls/ContentView.swift",
            "GitHalls/GIt/GitService.swift"
        ])
    }

    @Test func conflictMarkerPathsHandlesColonInPath() {
        let raw = "Docs/notes: draft.md:9: leftover conflict marker\n"

        #expect(MergeStateParser.conflictMarkerPaths(raw) == ["Docs/notes: draft.md"])
    }

    @Test func conflictMarkerPathsEmptyWhenClean() {
        #expect(MergeStateParser.conflictMarkerPaths("").isEmpty)
    }

    @Test func splitMessageDropsGitComments() {
        let raw = """
        Merge branch 'feature/graph' into main

        Keeps the lane colours from main.

        # Conflicts:
        #\tGitHalls/Views/GraphView.swift

        """

        let parts = MergeStateParser.splitMessage(raw)

        #expect(parts.summary == "Merge branch 'feature/graph' into main")
        #expect(parts.description == "Keeps the lane colours from main.")
    }

    @Test func splitMessageWithoutDescription() {
        let parts = MergeStateParser.splitMessage("Merge branch 'topic'\n")

        #expect(parts.summary == "Merge branch 'topic'")
        #expect(parts.description.isEmpty)
    }

    @Test func splitMessageOfCommentsOnly() {
        let parts = MergeStateParser.splitMessage("# Conflicts:\n#\tREADME.md\n")

        #expect(parts.summary.isEmpty)
        #expect(parts.description.isEmpty)
    }
}
