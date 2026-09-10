//
//  CommitFileParserTests.swift
//  GitHallsTests
//
//  Created by Lucas de Amorim on 10/09/26.
//

import Foundation
import Testing
@testable import GitHalls

struct CommitFileParserTests {

    @Test func modifiedFileCarriesLineCounts() {
        let raw = """
        :100644 100644 6179f2f 8b04a84 M\tGitHalls/ContentView.swift
        12\t3\tGitHalls/ContentView.swift
        """
        let files = CommitFileParser.parse(raw)

        #expect(files.count == 1)
        #expect(files[0].path == "GitHalls/ContentView.swift")
        #expect(files[0].status == .modified)
        #expect(files[0].addedLineCount == 12)
        #expect(files[0].removedLineCount == 3)
        #expect(files[0].originalPath == nil)
    }

    @Test func addedAndDeletedFiles() {
        let raw = """
        :000000 100644 0000000 6fade78 A\tNew.swift
        :100644 000000 b9f865e 0000000 D\tOld.swift
        4\t0\tNew.swift
        0\t9\tOld.swift
        """
        let files = CommitFileParser.parse(raw)

        #expect(files.count == 2)
        #expect(files[0].status == .added)
        #expect(files[0].addedLineCount == 4)
        #expect(files[1].status == .deleted)
        #expect(files[1].removedLineCount == 9)
    }

    @Test func renameKeepsBothPaths() {
        let raw = """
        :100644 100644 a29bdeb 972cf31 R066\ta.txt\tb dir/c.txt
        1\t0\ta.txt => b dir/c.txt
        """
        let files = CommitFileParser.parse(raw)

        #expect(files.count == 1)
        #expect(files[0].status == .renamed)
        #expect(files[0].path == "b dir/c.txt")
        #expect(files[0].originalPath == "a.txt")
        // Both sides, so git still sees one file rather than a delete and an add.
        #expect(files[0].pathspec == ["a.txt", "b dir/c.txt"])
        #expect(files[0].addedLineCount == 1)
    }

    @Test func binaryFileHasNoCounts() {
        let raw = """
        :000000 100644 0000000 1a2b3c4 A\tAssets/logo.png
        -\t-\tAssets/logo.png
        """
        let files = CommitFileParser.parse(raw)

        #expect(files[0].isBinary)
        #expect(files[0].addedLineCount == nil)
        #expect(files[0].removedLineCount == nil)
    }

    @Test func typeChangeCountsAsModified() {
        let raw = """
        :100644 120000 6179f2f 8b04a84 T\tlink.txt
        1\t1\tlink.txt
        """
        let files = CommitFileParser.parse(raw)

        #expect(files[0].status == .modified)
    }

    @Test func combinedMergeEntriesAreIgnored() {
        // "::" only turns up if the first-parent flag were dropped; the parser
        // has no before-state to attribute those to.
        let raw = """
        ::100644 100644 100644 abc def 012 MM\tconflicted.swift
        """
        #expect(CommitFileParser.parse(raw).isEmpty)
    }

    @Test func emptyOutputMeansNoFiles() {
        #expect(CommitFileParser.parse("").isEmpty)
        #expect(CommitFileParser.parse("\n").isEmpty)
    }
}
