//
//  DiffParserTests.swift
//  GitHallsTests
//
//  Created by Lucas de Amorim on 28/08/26.
//

import Foundation
import Testing
@testable import GitHalls

struct DiffParserTests {

    @Test func parsesAdditionsAndDeletions() {
        let raw = """
        diff --git a/file.swift b/file.swift
        index abc123..def456 100644
        --- a/file.swift
        +++ b/file.swift
        @@ -1,3 +1,3 @@
         unchanged line
        -removed line
        +added line
        """

        let diff = DiffParser.parse(raw)

        #expect(diff.path == "file.swift")
        #expect(diff.lines.contains { $0.kind == .context && $0.text == "unchanged line" })
        #expect(diff.lines.contains { $0.kind == .deletion && $0.text == "removed line" })
        #expect(diff.lines.contains { $0.kind == .addition && $0.text == "added line" })
    }

    @Test func hunkHeaderSetsStartingLineNumbers() {
        let raw = """
        diff --git a/file.swift b/file.swift
        --- a/file.swift
        +++ b/file.swift
        @@ -12,2 +12,3 @@
         context line
        +added line
        """

        let diff = DiffParser.parse(raw)

        let context = diff.lines.first { $0.kind == .context }
        #expect(context?.oldLineNumber == 12)
        #expect(context?.newLineNumber == 12)

        let addition = diff.lines.first { $0.kind == .addition }
        #expect(addition?.newLineNumber == 13)
        #expect(addition?.oldLineNumber == nil)
    }

    @Test func syntheticAllAdditionsNumbersEveryLine() {
        let diff = DiffParser.syntheticAllAdditions(path: "new.swift", content: "line1\nline2\nline3")

        // One hunk header, then the three lines.
        #expect(diff.lines.count == 4)
        #expect(diff.lines[0].kind == .hunkHeader)
        #expect(diff.lines.dropFirst().allSatisfy { $0.kind == .addition })
        #expect(diff.lines[1].newLineNumber == 1)
        #expect(diff.lines[3].newLineNumber == 3)
        #expect(diff.lines[3].noNewlineAtEnd)
    }

    @Test func syntheticAllAdditionsIgnoresTheTerminatingNewline() {
        let diff = DiffParser.syntheticAllAdditions(path: "new.swift", content: "a\nb\n")

        #expect(diff.lines.filter { $0.kind == .addition }.count == 2)
        #expect(diff.lines.allSatisfy { !$0.noNewlineAtEnd })
    }

    @Test func crlfLinesSplitAndKeepTheirRawEnding() {
        let raw = "diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-old\r\n+new\r\n"

        let diff = DiffParser.parse(raw)

        let added = diff.lines.first { $0.kind == .addition }
        #expect(added?.text == "new")
        #expect(added?.rawLine == "+new\r")
        #expect(diff.lines.count == 3)
    }

    @Test func noNewlineMarkerAttachesToThePrecedingLine() {
        let raw = "diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n"

        let diff = DiffParser.parse(raw)

        #expect(diff.lines.first { $0.kind == .deletion }?.noNewlineAtEnd == true)
        #expect(diff.lines.first { $0.kind == .addition }?.noNewlineAtEnd == false)
    }

    @Test func recordsHunkRangesAndFileKind() {
        let raw = "diff --git a/f b/f\nnew file mode 100644\n--- /dev/null\n+++ b/f\n@@ -0,0 +1,2 @@\n+a\n+b\n"

        let diff = DiffParser.parse(raw)

        #expect(diff.isNewFile)
        #expect(diff.lines[0].hunkRange == HunkRange(oldStart: 0, oldCount: 0, newStart: 1, newCount: 2))
        #expect(diff.patchHeader.count == 4)
    }
}
