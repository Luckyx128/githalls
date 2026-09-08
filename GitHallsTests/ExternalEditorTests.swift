//
//  ExternalEditorTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct ExternalEditorTests {
    @Test func listsEachEditorOnce() {
        let ids = ExternalEditors.known.map(\.bundleIdentifier)

        #expect(ids.count == Set(ids).count)
    }

    @Test func namesEveryEditorItOffers() {
        #expect(ExternalEditors.known.allSatisfy { !$0.name.isEmpty && !$0.bundleIdentifier.isEmpty })
    }

    @Test func offersOnlyWhatIsInstalled() {
        // A subset by construction — the point is that an identifier matching
        // nothing on this Mac drops out rather than producing a dead menu item.
        let known = Set(ExternalEditors.known.map(\.id))

        #expect(ExternalEditors.installed.allSatisfy { known.contains($0.id) })
    }
}
