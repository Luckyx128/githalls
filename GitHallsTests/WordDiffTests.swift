//
//  WordDiffTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct WordDiffTests {
    private func slice(_ text: String, _ ranges: [Range<Int>]) -> [String] {
        let units = Array(text.utf16)
        return ranges.map { String(decoding: units[$0], as: UTF16.self) }
    }

    @Test func tokenizesWordsBlanksAndPunctuation() {
        let tokens = WordDiff.tokenize("foo_1  = bar(x);").map(\.text)
        #expect(tokens == ["foo_1", "  ", "=", " ", "bar", "(", "x", ")", ";"])
    }

    @Test func tokenRangesAreUTF16Offsets() {
        let tokens = WordDiff.tokenize("é😀x")
        #expect(tokens.last?.range == 3..<4)
    }

    @Test func marksOnlyTheChangedWord() throws {
        let old = "let count = items.count"
        let new = "let total = items.count"
        let result = try #require(WordDiff.compare(old: old, new: new))
        #expect(slice(old, result.oldRanges) == ["count"])
        #expect(slice(new, result.newRanges) == ["total"])
    }

    @Test func marksInsertedArgument() throws {
        let old = "call(a)"
        let new = "call(a, b)"
        let result = try #require(WordDiff.compare(old: old, new: new))
        #expect(result.oldRanges.isEmpty)
        #expect(slice(new, result.newRanges) == [", b"])
    }

    @Test func changedWordsSeparatedByBlankMergeIntoOneRange() throws {
        let old = "return alpha beta end"
        let new = "return gamma delta end"
        let result = try #require(WordDiff.compare(old: old, new: new))
        #expect(slice(old, result.oldRanges) == ["alpha beta"])
        #expect(slice(new, result.newRanges) == ["gamma delta"])
    }

    @Test func unrelatedLinesAreNotPaired() {
        #expect(WordDiff.compare(old: "    alpha(beta)", new: "    totally different text") == nil)
    }

    @Test func sharedIndentDoesNotMakeLinesSimilar() {
        #expect(WordDiff.compare(old: "            foo", new: "            quuxbar") == nil)
    }

    @Test func longLinesAreSkipped() {
        let long = String(repeating: "a ", count: 300)
        #expect(WordDiff.compare(old: long, new: long + "b") == nil)
    }

    @Test func identicalLinesHaveNothingToMark() throws {
        let result = try #require(WordDiff.compare(old: "same line", new: "same line"))
        #expect(result.oldRanges.isEmpty && result.newRanges.isEmpty)
    }

    @Test func pairsRunsByPositionWithinAHunk() {
        let kinds: [DiffLine.Kind] = [.context, .deletion, .deletion, .addition, .addition, .context, .addition]
        let texts = ["x", "let a = 1", "let b = 2", "let a = 10", "let b = 20", "y", "z"]
        let pairs = WordDiff.pairs(kinds: kinds, texts: texts)
        #expect(Set(pairs.keys) == [1, 2, 3, 4])
        #expect(slice(texts[1], pairs[1] ?? []) == ["1"])
        #expect(slice(texts[4], pairs[4] ?? []) == ["20"])
    }

    @Test func lonelyRunsAreNotPaired() {
        let pairs = WordDiff.pairs(kinds: [.addition, .context, .deletion], texts: ["a", "b", "c"])
        #expect(pairs.isEmpty)
    }
}
