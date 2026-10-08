//
//  PatchBuilderTests.swift
//  GitHallsTests
//
//  The first half checks the text of the patches; the second runs them through
//  a real `git apply` in a throwaway repository, because "looks right" and
//  "git accepts it and ends up with the right file" are different claims.
//

import Foundation
import Testing
@testable import GitHalls

struct PatchBuilderTests {

    /// Indices of the changed lines whose text is one of `texts`, in `kind`.
    private func pick(_ diff: FileDiff, _ pairs: [(DiffLine.Kind, String)]) -> Set<Int> {
        var result: Set<Int> = []
        for (kind, text) in pairs {
            guard let index = diff.lines.firstIndex(where: { $0.kind == kind && $0.text == text }) else {
                Issue.record("no \(kind) line \"\(text)\"")
                continue
            }
            result.insert(index)
        }
        return result
    }

    private let header = "diff --git a/f.txt b/f.txt\nindex 1..2 100644\n--- a/f.txt\n+++ b/f.txt\n"

    // MARK: - Text

    @Test func stagesASingleAddedLine() {
        let diff = DiffParser.parse(header + "@@ -1,2 +1,4 @@\n one\n+two\n+three\n four\n")

        let patch = PatchBuilder.build(diff: diff, selected: pick(diff, [(.addition, "two")]), direction: .forward)

        #expect(patch == "diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1,2 +1,3 @@\n one\n+two\n four\n")
    }

    @Test func stagesASingleDeletedLine() {
        let diff = DiffParser.parse(header + "@@ -1,4 +1,2 @@\n one\n-two\n-three\n four\n")

        let patch = PatchBuilder.build(diff: diff, selected: pick(diff, [(.deletion, "three")]), direction: .forward)

        // "two" stays in the file, so it is context.
        #expect(patch == "diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1,4 +1,3 @@\n one\n two\n-three\n four\n")
    }

    @Test func mixedSelectionWithinOneHunk() {
        let diff = DiffParser.parse(header + "@@ -1,3 +1,3 @@\n a\n-b\n-c\n+B\n+C\n d\n")

        let patch = PatchBuilder.build(diff: diff,
                                       selected: pick(diff, [(.deletion, "b"), (.addition, "C")]),
                                       direction: .forward)

        #expect(patch?.contains("@@ -1,4 +1,4 @@\n a\n-b\n c\n+C\n d\n") == true)
    }

    @Test func hunksWithNothingSelectedAreDropped() {
        let diff = DiffParser.parse(header + "@@ -1,2 +1,3 @@\n a\n+x\n b\n@@ -10,2 +11,3 @@\n j\n+y\n k\n")

        let patch = PatchBuilder.build(diff: diff, selected: pick(diff, [(.addition, "y")]), direction: .forward)

        #expect(patch?.contains("+x\n") == false)
        #expect(patch?.contains("@@ -10,2 +10,3 @@") == true)
    }

    /// Hunk one adds a line that stays unstaged, so by the second hunk the new
    /// side is no longer eleven lines in — the header must say so.
    @Test func laterHunksFollowTheEarlierOnes() {
        let diff = DiffParser.parse(header + "@@ -1,2 +1,3 @@\n a\n+x\n b\n@@ -10,2 +11,3 @@\n j\n+y\n k\n")

        let both = PatchBuilder.build(diff: diff,
                                      selected: pick(diff, [(.addition, "x"), (.addition, "y")]),
                                      direction: .forward)
        #expect(both?.contains("@@ -1,2 +1,3 @@") == true)
        #expect(both?.contains("@@ -10,2 +11,3 @@") == true)

        let second = PatchBuilder.build(diff: diff, selected: pick(diff, [(.addition, "y")]), direction: .forward)
        #expect(second?.contains("@@ -10,2 +10,3 @@") == true)
    }

    @Test func reverseDropsUnselectedDeletionsAndKeepsUnselectedAdditions() {
        let diff = DiffParser.parse(header + "@@ -1,3 +1,3 @@\n a\n-b\n+B\n+C\n d\n")

        let patch = PatchBuilder.build(diff: diff, selected: pick(diff, [(.addition, "B")]), direction: .reverse)

        // "b" is not in the file being reversed; "C" is, and stays as context.
        #expect(patch?.contains("@@ -1,3 +1,4 @@\n a\n+B\n C\n d\n") == true)
    }

    @Test func nothingSelectedYieldsNoPatch() {
        let diff = DiffParser.parse(header + "@@ -1,2 +1,3 @@\n a\n+x\n b\n")

        #expect(PatchBuilder.build(diff: diff, selected: [], direction: .forward) == nil)
        // A context line is not a change.
        #expect(PatchBuilder.build(diff: diff, selected: pick(diff, [(.context, "a")]), direction: .forward) == nil)
    }

    @Test func binaryDiffsGetNoPatch() {
        let diff = DiffParser.parse("diff --git a/i.png b/i.png\nBinary files a/i.png and b/i.png differ\n")

        #expect(PatchBuilder.build(diff: diff, selected: [0, 1], direction: .forward) == nil)
    }

    @Test func noNewlineMarkersFollowTheirLines() {
        let raw = header + "@@ -1,2 +1,2 @@\n a\n-b\n\\ No newline at end of file\n+c\n\\ No newline at end of file\n"
        let diff = DiffParser.parse(raw)

        let all = PatchBuilder.build(diff: diff, selected: PatchBuilder.allChanged(in: diff), direction: .forward)
        #expect(all?.hasSuffix("-b\n\\ No newline at end of file\n+c\n\\ No newline at end of file\n") == true)

        // Dropping "+c" takes its marker with it; "-b" turned into context keeps its own.
        let onlyAdd = PatchBuilder.build(diff: diff, selected: pick(diff, [(.deletion, "b")]), direction: .forward)
        #expect(onlyAdd?.hasSuffix("-b\n\\ No newline at end of file\n") == true)
        #expect(onlyAdd?.contains("+c") == false)
    }

    @Test func crlfStaysByteExact() {
        let crlf = header + "@@ -1,2 +1,3 @@\n a\r\n+x\r\n b\r\n"
        let diff = DiffParser.parse(crlf)

        let patch = PatchBuilder.build(diff: diff, selected: pick(diff, [(.addition, "x")]), direction: .forward)

        #expect(patch?.hasSuffix("@@ -1,2 +1,3 @@\n a\r\n+x\r\n b\r\n") == true)
    }

    @Test func newFilePatchStartsAtLineOne() {
        let diff = DiffParser.syntheticAllAdditions(path: "n.txt", content: "a\nb\nc\n")

        let patch = PatchBuilder.build(diff: diff, selected: pick(diff, [(.addition, "b")]), direction: .forward)

        #expect(patch == "diff --git a/n.txt b/n.txt\nnew file mode 100644\n--- /dev/null\n+++ b/n.txt\n@@ -0,0 +1 @@\n+b\n")
    }

    // MARK: - Real git

    private func makeRepo() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "githalls-patch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git(["init", "-q"], in: url)
        try git(["config", "user.email", "t@example.com"], in: url)
        try git(["config", "user.name", "T"], in: url)
        try git(["config", "core.autocrlf", "false"], in: url)
        return url
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func write(_ text: String, _ name: String, in repo: URL) throws {
        try Data(text.utf8).write(to: repo.appending(path: name))
    }

    private func read(_ name: String, in repo: URL) throws -> String {
        String(decoding: try Data(contentsOf: repo.appending(path: name)), as: UTF8.self)
    }

    private func diff(_ arguments: [String], in repo: URL) throws -> FileDiff {
        DiffParser.parse(try git(["diff", "--no-color"] + arguments, in: repo))
    }

    private let base = (1...12).map { "line \($0)" }.joined(separator: "\n") + "\n"

    @Test func stagesChosenLinesAcrossHunks() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write(base, "f.txt", in: repo)
        try git(["add", "."], in: repo)
        try git(["commit", "-q", "-m", "base"], in: repo)

        var edited = base.components(separatedBy: "\n")
        edited[1] = "line 2 changed"
        edited.insert("inserted after 2", at: 2)
        edited.remove(at: 10)           // drops "line 10" (index shifted by the insert)
        try write(edited.joined(separator: "\n"), "f.txt", in: repo)

        let unstaged = try diff(["--", "f.txt"], in: repo)
        #expect(unstaged.hunkCount == 2)
        let selected = pick(unstaged, [(.addition, "inserted after 2"), (.deletion, "line 10")])
        let patch = try #require(PatchBuilder.build(diff: unstaged, selected: selected, direction: .forward))

        let service = GitService()
        try await service.applyPatch(at: repo, patch: patch, cached: true, reverse: false)

        let cached = try git(["diff", "--cached", "--no-color"], in: repo)
        #expect(cached.contains("+inserted after 2"))
        #expect(cached.contains("-line 10"))
        #expect(!cached.contains("line 2 changed"))
        // What was left out is still a worktree change.
        let rest = try git(["diff", "--no-color"], in: repo)
        #expect(rest.contains("+line 2 changed"))
        #expect(!rest.contains("+inserted after 2"))
    }

    @Test func unstagesChosenLines() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write(base, "f.txt", in: repo)
        try git(["add", "."], in: repo)
        try git(["commit", "-q", "-m", "base"], in: repo)

        var edited = base.components(separatedBy: "\n")
        edited[0] = "first"
        edited[8] = "ninth"
        try write(edited.joined(separator: "\n"), "f.txt", in: repo)
        try git(["add", "f.txt"], in: repo)

        let staged = try diff(["--cached", "--", "f.txt"], in: repo)
        let selected = pick(staged, [(.addition, "ninth"), (.deletion, "line 9")])
        let patch = try #require(PatchBuilder.build(diff: staged, selected: selected, direction: .reverse))

        try await GitService().applyPatch(at: repo, patch: patch, cached: true, reverse: true)

        let cached = try git(["diff", "--cached", "--no-color"], in: repo)
        #expect(cached.contains("+first"))
        #expect(!cached.contains("ninth"))
        // The working tree is untouched.
        #expect(try read("f.txt", in: repo).contains("ninth"))
    }

    @Test func discardsChosenLinesFromTheWorkingTree() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write(base, "f.txt", in: repo)
        try git(["add", "."], in: repo)
        try git(["commit", "-q", "-m", "base"], in: repo)

        var edited = base.components(separatedBy: "\n")
        edited[0] = "first"
        edited[8] = "ninth"
        try write(edited.joined(separator: "\n"), "f.txt", in: repo)

        let unstaged = try diff(["--", "f.txt"], in: repo)
        let selected = pick(unstaged, [(.addition, "ninth"), (.deletion, "line 9")])
        let patch = try #require(PatchBuilder.build(diff: unstaged, selected: selected, direction: .reverse))

        try await GitService().applyPatch(at: repo, patch: patch, cached: false, reverse: true)

        let text = try read("f.txt", in: repo)
        #expect(text.contains("line 9"))
        #expect(!text.contains("ninth"))
        #expect(text.hasPrefix("first\n"))
    }

    @Test func stagesPartOfAnUntrackedFile() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write("seed\n", "seed.txt", in: repo)
        try git(["add", "."], in: repo)
        try git(["commit", "-q", "-m", "base"], in: repo)
        try write("a\nb\nc\nd\n", "new.txt", in: repo)

        let service = GitService()
        let change = FileChange(path: "new.txt", originalPath: nil, indexStatus: "?", worktreeStatus: "?", status: .untracked)
        let synthetic = try await service.diff(at: repo, for: change)
        let patch = try #require(PatchBuilder.build(diff: synthetic,
                                                    selected: pick(synthetic, [(.addition, "b"), (.addition, "c")]),
                                                    direction: .forward))

        try await service.applyPatch(at: repo, patch: patch, cached: true, reverse: false)

        #expect(try git(["show", ":new.txt"], in: repo) == "b\nc\n")
        #expect(try read("new.txt", in: repo) == "a\nb\nc\nd\n")
        #expect(try git(["status", "--porcelain"], in: repo).contains("AM new.txt"))
    }

    @Test func crlfFilesStageByteExact() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write("a\r\nb\r\nc\r\n", "w.txt", in: repo)
        try git(["add", "."], in: repo)
        try git(["commit", "-q", "-m", "base"], in: repo)
        try write("a\r\nB\r\nc\r\nd\r\n", "w.txt", in: repo)

        let unstaged = try diff(["--", "w.txt"], in: repo)
        let patch = try #require(PatchBuilder.build(diff: unstaged,
                                                    selected: pick(unstaged, [(.addition, "d")]),
                                                    direction: .forward))
        try await GitService().applyPatch(at: repo, patch: patch, cached: true, reverse: false)

        #expect(try git(["show", ":w.txt"], in: repo) == "a\r\nb\r\nc\r\nd\r\n")
    }

    @Test func noNewlineAtEndOfFileRoundTrips() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write("a\nb", "e.txt", in: repo)
        try git(["add", "."], in: repo)
        try git(["commit", "-q", "-m", "base"], in: repo)
        // Both lines change, and the new last line is newline-terminated.
        try write("A\nb\nc\n", "e.txt", in: repo)

        let unstaged = try diff(["--", "e.txt"], in: repo)
        let all = PatchBuilder.allChanged(in: unstaged)
        let patch = try #require(PatchBuilder.build(diff: unstaged, selected: all, direction: .forward))
        try await GitService().applyPatch(at: repo, patch: patch, cached: true, reverse: false)

        #expect(try git(["show", ":e.txt"], in: repo) == "A\nb\nc\n")

        // And back out again, reversed.
        let staged = try diff(["--cached", "--", "e.txt"], in: repo)
        let undo = try #require(PatchBuilder.build(diff: staged, selected: PatchBuilder.allChanged(in: staged), direction: .reverse))
        try await GitService().applyPatch(at: repo, patch: undo, cached: true, reverse: true)
        #expect(try git(["show", ":e.txt"], in: repo) == "a\nb")
    }

    @Test func stagingTheOneDeletionNextToAnEdit() async throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try write("a\nb\nc\n", "m.txt", in: repo)
        try git(["add", "."], in: repo)
        try git(["commit", "-q", "-m", "base"], in: repo)
        try write("a\nX\nY\n", "m.txt", in: repo)

        let unstaged = try diff(["--", "m.txt"], in: repo)
        let patch = try #require(PatchBuilder.build(diff: unstaged,
                                                    selected: pick(unstaged, [(.deletion, "b"), (.addition, "X")]),
                                                    direction: .forward))
        try await GitService().applyPatch(at: repo, patch: patch, cached: true, reverse: false)

        // The deletion of "c" is not staged, so it sits between the two.
        #expect(try git(["show", ":m.txt"], in: repo) == "a\nc\nX\n")
    }
}
