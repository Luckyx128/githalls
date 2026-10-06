//
//  ExternalEditorTests.swift
//  GitHallsTests
//

import Foundation
import Testing
@testable import GitHalls

struct ExternalEditorTests {
    @Test func listsEachEditorOnce() {
        let ids = ExternalEditors.known.map(\.id)

        #expect(ids.count == Set(ids).count)
    }

    @Test func namesEveryEditorItOffers() {
        #expect(ExternalEditors.known.allSatisfy { !$0.name.isEmpty && !$0.id.isEmpty })
    }

    @Test func offersOnlyWhatIsInstalled() {
        // A subset by construction — the point is that an identifier matching
        // nothing on this Mac drops out rather than producing a dead menu item.
        let known = Set(ExternalEditors.known.map(\.id))

        #expect(ExternalEditors.installed.allSatisfy { known.contains($0.id) })
    }

    @Test func knowsNeovim() {
        #expect(ExternalEditors.known.contains { $0.id == "terminal:nvim" })
    }

    @Test func offersWarpAsATerminal() {
        let ids = ExternalEditors.knownTerminals.map(\.id)

        #expect(ids.contains("dev.warp.Warp-Stable"))
        #expect(ids.count == Set(ids).count)
    }

    @Test func quotesPathsForTheShell() {
        #expect(ExternalEditors.shellQuoted("/tmp/it's here") == "'/tmp/it'\\''s here'")
    }

    @Test func launchScriptOpensEveryFileFromTheRepository() {
        let script = ExternalEditors.launchScript(
            executable: "/opt/homebrew/bin/nvim",
            directory: URL(fileURLWithPath: "/repo"),
            files: [URL(fileURLWithPath: "/repo/a.swift"), URL(fileURLWithPath: "/repo/b c.swift")]
        )

        #expect(script.contains("cd '/repo' || exit 1"))
        #expect(script.contains("exec '/opt/homebrew/bin/nvim' -p '/repo/a.swift' '/repo/b c.swift'"))
    }
}
