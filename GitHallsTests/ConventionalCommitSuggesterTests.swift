//
//  ConventionalCommitSuggesterTests.swift
//  GitHallsTests
//
//  Created by Lucas de Amorim on 31/08/26.
//

import Testing
@testable import GitHalls

struct ConventionalCommitSuggesterTests {

    private func change(path: String, status: FileChange.Status) -> FileChange {
        FileChange(path: path, originalPath: nil, indexStatus: " ", worktreeStatus: " ", status: status)
    }

    @Test func suggestsTestForTestFiles() {
        let changes = [change(path: "GitHallsTests/FooTests.swift", status: .modified)]
        #expect(ConventionalCommitSuggester.suggestedType(for: changes) == .test)
    }

    @Test func suggestsDocsForMarkdownFiles() {
        let changes = [change(path: "README.md", status: .modified)]
        #expect(ConventionalCommitSuggester.suggestedType(for: changes) == .docs)
    }

    @Test func suggestsFeatForAllNewFiles() {
        let changes = [change(path: "GitHalls/Views/NewView.swift", status: .untracked)]
        #expect(ConventionalCommitSuggester.suggestedType(for: changes) == .feat)
    }

    @Test func suggestsFixAsDefaultForModifiedFiles() {
        let changes = [change(path: "GitHalls/Views/ExistingView.swift", status: .modified)]
        #expect(ConventionalCommitSuggester.suggestedType(for: changes) == .fix)
    }

    @Test func suggestsScopeWhenAllFilesShareTopFolder() {
        let changes = [
            change(path: "GitHalls/Views/A.swift", status: .modified),
            change(path: "GitHalls/Views/B.swift", status: .modified)
        ]
        #expect(ConventionalCommitSuggester.suggestedScope(for: changes) == "githalls")
    }

    @Test func noScopeWhenFilesSpanDifferentFolders() {
        let changes = [
            change(path: "GitHalls/A.swift", status: .modified),
            change(path: "GitHallsTests/B.swift", status: .modified)
        ]
        #expect(ConventionalCommitSuggester.suggestedScope(for: changes) == nil)
    }
}
