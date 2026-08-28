//
//  StatusParserTests.swift
//  GitHallsTests
//
//  Created by Lucas de Amorim on 28/08/26.
//

import Foundation
import Testing
@testable import GitHalls

struct StatusParserTests {

    @Test func modifiedFile() {
        let raw = " M GitHalls/ContentView.swift\n"
        let changes = StatusParser.parse(raw)

        #expect(changes.count == 1)
        #expect(changes[0].path == "GitHalls/ContentView.swift")
        #expect(changes[0].status == .modified)
    }

    @Test func untrackedFile() {
        let raw = "?? GitHalls/NewFile.swift\n"
        let changes = StatusParser.parse(raw)

        #expect(changes.count == 1)
        #expect(changes[0].status == .untracked)
    }

    @Test func addedFile() {
        let raw = "A  GitHalls/NewFile.swift\n"
        let changes = StatusParser.parse(raw)

        #expect(changes[0].status == .added)
    }

    @Test func deletedFile() {
        let raw = " D GitHalls/OldFile.swift\n"
        let changes = StatusParser.parse(raw)

        #expect(changes[0].status == .deleted)
    }

    @Test func renamedFile() {
        let raw = "R  GitHalls/Old.swift -> GitHalls/New.swift\n"
        let changes = StatusParser.parse(raw)

        #expect(changes.count == 1)
        #expect(changes[0].status == .renamed)
        #expect(changes[0].originalPath == "GitHalls/Old.swift")
        #expect(changes[0].path == "GitHalls/New.swift")
    }

    @Test func multipleLines() {
        let raw = " M GitHalls/A.swift\n?? GitHalls/B.swift\n D GitHalls/C.swift\n"
        let changes = StatusParser.parse(raw)

        #expect(changes.count == 3)
    }

    @Test func emptyOutputProducesNoChanges() {
        #expect(StatusParser.parse("").isEmpty)
    }
}
