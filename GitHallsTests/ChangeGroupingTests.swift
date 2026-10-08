//
//  ChangeGroupingTests.swift
//  GitHallsTests
//

import Foundation
import Testing
@testable import GitHalls

@MainActor
struct ChangeGroupingTests {

    private func viewModel(_ raw: String) -> RepositoryViewModel {
        let model = RepositoryViewModel()
        model.changes = StatusParser.parse(raw)
        return model
    }

    /// Git prints untracked files after everything else. Left in that order, a
    /// new file jumps up the list the moment it is staged.
    @Test func untrackedFilesSortInWithTheRest() {
        let model = viewModel("""
             M a.txt
             M z.txt
            ?? b.txt

            """)

        #expect(model.sortedChanges.map(\.path) == ["a.txt", "b.txt", "z.txt"])
    }

    @Test func stagingDoesNotMoveARowWithinItsGroup() {
        let before = viewModel("""
             M a.txt
             M z.txt
            ?? b.txt

            """)
        let after = viewModel("""
             M a.txt
             M z.txt
            A  b.txt

            """)

        #expect(before.sortedChanges.map(\.path) == after.sortedChanges.map(\.path))
    }

    @Test func splitsStagedFromUnstaged() {
        let model = viewModel("""
            M  staged.txt
             M unstaged.txt
            ?? new.txt

            """)

        #expect(model.stagedChanges.map(\.path) == ["staged.txt"])
        #expect(model.unstagedChanges.map(\.path) == ["new.txt", "unstaged.txt"])
    }

    /// A file staged with further edits on disk (`MM`) has a row in each section.
    @Test func partiallyStagedFileAppearsInBothGroups() {
        let model = viewModel("MM both.txt\n")

        #expect(model.stagedChanges.map(\.path) == ["both.txt"])
        #expect(model.unstagedChanges.map(\.path) == ["both.txt"])
        #expect(model.changes[0].isPartiallyStaged)
    }

    @Test func fullyStagedFileIsNotPartial() {
        let model = viewModel("M  done.txt\n")

        #expect(!model.changes[0].isPartiallyStaged)
        #expect(model.unstagedChanges.isEmpty)
    }

    /// Two rows share one file id, so the list tags them by side.
    @Test func sidebarSelectionRemembersWhichSection() {
        let model = viewModel("MM both.txt\n")

        model.sidebarSelection = RepositoryViewModel.sidebarTag("both.txt", side: .staged)

        #expect(model.selectedChangeID == "both.txt")
        #expect(model.selectedDiffSide == .staged)

        model.sidebarSelection = RepositoryViewModel.sidebarTag("both.txt", side: .unstaged)
        #expect(model.selectedDiffSide == .unstaged)
    }

    /// Conflicts get their own section, so neither group may claim them.
    @Test func conflictsStayOutOfBothGroups() {
        let model = viewModel("""
            UU conflicted.txt
             M plain.txt

            """)

        #expect(model.stagedChanges.isEmpty)
        #expect(model.unstagedChanges.map(\.path) == ["plain.txt"])
        #expect(model.conflictedChanges.map(\.path) == ["conflicted.txt"])
    }
}
