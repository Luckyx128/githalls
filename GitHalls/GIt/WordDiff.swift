//
//  WordDiff.swift
//  GitHalls
//
//  Token-level comparison of one removed line against the line that replaced
//  it, so the diff can tint the words that really changed and leave the rest
//  of the line at the plain +/- tint.
//

import Foundation

nonisolated enum WordDiff {
    /// Lines longer than this (in UTF-16 units) are not compared.
    static let maxLineLength = 500
    /// Below this share of shared non-blank text, two lines are different
    /// lines rather than an edit of one, and tinting words would be noise.
    static let minSimilarity = 0.4

    struct Token: Equatable {
        let text: String
        /// UTF-16 offsets into the line.
        let range: Range<Int>
    }

    struct Result: Equatable {
        /// UTF-16 ranges of the old / new line that differ.
        var oldRanges: [Range<Int>]
        var newRanges: [Range<Int>]
        /// Shared non-blank text over all non-blank text, 0...1.
        var similarity: Double
    }

    private enum Class { case word, space, other }

    private static func classify(_ scalar: Unicode.Scalar) -> Class {
        if scalar == "_" || CharacterSet.alphanumerics.contains(scalar) { return .word }
        if CharacterSet.whitespaces.contains(scalar) { return .space }
        return .other
    }

    /// Words (letters, digits, `_`) and blank runs stay whole; every other
    /// character is a token of its own, so `foo()` → `foo(x)` marks only `x`.
    static func tokenize(_ line: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentClass: Class?
        var start = 0
        var offset = 0

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(Token(text: current, range: start..<offset))
            current = ""
        }

        for scalar in line.unicodeScalars {
            let kind = classify(scalar)
            if kind == .other || kind != currentClass {
                flush()
                start = offset
            }
            current.unicodeScalars.append(scalar)
            currentClass = kind
            offset += scalar.utf16.count
        }
        flush()
        return tokens
    }

    /// Returns nil when either line is too long to bother with, or when the
    /// two are not alike enough to read as an edit of one another.
    static func compare(old: String, new: String,
                        maxLength: Int = maxLineLength,
                        minSimilarity: Double = minSimilarity) -> Result? {
        guard old.utf16.count <= maxLength, new.utf16.count <= maxLength else { return nil }

        let a = tokenize(old)
        let b = tokenize(new)

        // Shared head and tail need no table, and are most of a typical edit.
        var head = 0
        while head < a.count, head < b.count, a[head].text == b[head].text { head += 1 }
        var tail = 0
        while tail < a.count - head, tail < b.count - head,
              a[a.count - 1 - tail].text == b[b.count - 1 - tail].text { tail += 1 }

        let am = Array(a[head..<(a.count - tail)])
        let bm = Array(b[head..<(b.count - tail)])

        var oldKept = [Bool](repeating: true, count: a.count)
        var newKept = [Bool](repeating: true, count: b.count)
        for i in 0..<am.count { oldKept[head + i] = false }
        for j in 0..<bm.count { newKept[head + j] = false }

        // Longest common subsequence of what is left in the middle.
        if !am.isEmpty, !bm.isEmpty {
            let n = am.count
            let m = bm.count
            var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
            let width = m + 1
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i * width + j] = am[i].text == bm[j].text
                        ? table[(i + 1) * width + j + 1] + 1
                        : max(table[(i + 1) * width + j], table[i * width + j + 1])
                }
            }
            var i = 0
            var j = 0
            while i < n, j < m {
                if am[i].text == bm[j].text {
                    oldKept[head + i] = true
                    newKept[head + j] = true
                    i += 1; j += 1
                } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                    i += 1
                } else {
                    j += 1
                }
            }
        }

        let sharedLength = zip(a, oldKept).reduce(0) { $0 + ($1.1 ? nonBlankLength($1.0) : 0) }
        let total = a.reduce(0) { $0 + nonBlankLength($1) } + b.reduce(0) { $0 + nonBlankLength($1) }
        let similarity = total == 0 ? 1 : Double(2 * sharedLength) / Double(total)
        guard similarity >= minSimilarity else { return nil }

        return Result(oldRanges: changedRanges(a, kept: oldKept),
                      newRanges: changedRanges(b, kept: newKept),
                      similarity: similarity)
    }

    private static func nonBlankLength(_ token: Token) -> Int {
        token.text.unicodeScalars.contains { classify($0) != .space } ? token.range.count : 0
    }

    /// Adjacent changed tokens become one range, and so do two changed tokens
    /// with only blanks between them — `foo bar` replaced is one mark, not two.
    private static func changedRanges(_ tokens: [Token], kept: [Bool]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var index = 0
        while index < tokens.count {
            guard !kept[index] else { index += 1; continue }
            var end = tokens[index].range.upperBound
            var next = index + 1
            while next < tokens.count {
                if !kept[next] {
                    end = tokens[next].range.upperBound
                    next += 1
                } else if next + 1 < tokens.count, !kept[next + 1],
                          tokens[next].text.unicodeScalars.allSatisfy({ classify($0) == .space }) {
                    end = tokens[next + 1].range.upperBound
                    next += 2
                } else {
                    break
                }
            }
            ranges.append(tokens[index].range.lowerBound..<end)
            index = next
        }
        return ranges
    }

    /// Pairs for a hunk's lines: each run of deletions followed directly by a
    /// run of additions is matched by position. Returns, per line index, the
    /// ranges to tint. `budget` bounds the characters compared in total.
    static func pairs(kinds: [DiffLine.Kind], texts: [String], budget: Int = 20_000_000) -> [Int: [Range<Int>]] {
        var result: [Int: [Range<Int>]] = [:]
        var remaining = budget
        var index = 0
        while index < kinds.count {
            guard kinds[index] == .deletion else { index += 1; continue }
            var deletions: [Int] = []
            while index < kinds.count, kinds[index] == .deletion { deletions.append(index); index += 1 }
            var additions: [Int] = []
            while index < kinds.count, kinds[index] == .addition { additions.append(index); index += 1 }

            for (d, a) in zip(deletions, additions) {
                let cost = texts[d].utf16.count * texts[a].utf16.count
                guard cost <= remaining else { continue }
                remaining -= cost
                guard let diff = compare(old: texts[d], new: texts[a]) else { continue }
                if !diff.oldRanges.isEmpty { result[d] = diff.oldRanges }
                if !diff.newRanges.isEmpty { result[a] = diff.newRanges }
            }
        }
        return result
    }
}
