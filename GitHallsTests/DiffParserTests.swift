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

        #expect(diff.lines.count == 3)
        #expect(diff.lines.allSatisfy { $0.kind == .addition })
        #expect(diff.lines[0].newLineNumber == 1)
        #expect(diff.lines[2].newLineNumber == 3)
    }
}
