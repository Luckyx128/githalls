//
//  FileDiff.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation

/// Which half of a partly staged file a diff shows.
enum DiffSide: Equatable {
    case unstaged, staged
}

/// The numbers in an `@@ -a,b +c,d @@` header.
struct HunkRange: Equatable {
    var oldStart: Int
    var oldCount: Int
    var newStart: Int
    var newCount: Int
}

struct DiffLine: Identifiable {
    enum Kind: Hashable {
        case addition, deletion, context, hunkHeader
        /// Display only: the "show more lines" row between hunks.
        case expander
    }

    let id = UUID()
    let kind: Kind
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    /// The line exactly as git wrote it — marker included, `\r` kept, no `\n`.
    /// `text` is for display; a patch has to be rebuilt from this, or a CRLF
    /// file would come back with its line endings quietly changed.
    var rawLine: String?

    /// Which hunk the line (or header) belongs to; nil outside any hunk.
    var hunkIndex: Int?

    /// Set on hunk headers only.
    var hunkRange: HunkRange?

    /// A `\ No newline at end of file` marker followed this line.
    var noNewlineAtEnd = false

    var isChange: Bool { kind == .addition || kind == .deletion }

    /// Display diffs only (see `ContextExpander`): the position of this line in
    /// the real `FileDiff.lines`, or nil for a row that exists only on screen.
    var sourceIndex: Int?

    /// Set on expander rows only.
    var expander: ExpanderRow?
}

/// What an expander row offers, and where in its text each offer sits.
struct ExpanderRow: Equatable {
    enum Direction: Equatable {
        /// Reveal lines just above the next hunk.
        case up
        /// Reveal lines just below the previous hunk.
        case down
        case all
    }

    struct Action: Equatable {
        let direction: Direction
        /// UTF-16 range of the label inside the row's text.
        let range: Range<Int>
    }

    /// 0 is the stretch before the first hunk, n the one after hunk n-1.
    let gap: Int
    let actions: [Action]
}

struct FileDiff {
    let path: String
    var lines: [DiffLine]

    /// git had no text to diff. The lines then hold a notice and nothing else,
    /// and what the file actually is — an image, or something to open elsewhere
    /// — is decided from the path by `FilePreview`.
    var isBinary = false

    /// The raw lines before the first hunk that a patch still needs: the
    /// `diff --git`, `new file mode` / `deleted file mode` and `---` / `+++`
    /// lines. `index` and mode-change lines are left out on purpose, so a
    /// partial patch never drags a mode change along with it.
    var patchHeader: [String] = []
    var isNewFile = false
    var isDeletedFile = false
    var isRename = false

    /// Made by `ContextExpander`: has extra context rows and expander rows, so
    /// `lines` no longer lines up with what a patch is built from. Rows that
    /// came from the real diff say where in `sourceIndex`.
    var isDisplayView = false

    /// Index in the real diff of the line at `row` of this one; nil for a row
    /// that is not part of the real diff.
    func realIndex(ofRow row: Int) -> Int? {
        guard lines.indices.contains(row) else { return nil }
        return isDisplayView ? lines[row].sourceIndex : row
    }

    /// The inverse of `realIndex(ofRow:)`.
    func row(ofRealIndex index: Int) -> Int? {
        isDisplayView ? lines.firstIndex { $0.sourceIndex == index } : (lines.indices.contains(index) ? index : nil)
    }

    var hunkCount: Int { (lines.compactMap(\.hunkIndex).max() ?? -1) + 1 }

    /// Same text, line for line — what decides whether a reload changed anything.
    func hasSameContent(as other: FileDiff) -> Bool {
        path == other.path && isBinary == other.isBinary && lines.count == other.lines.count
            && zip(lines, other.lines).allSatisfy { $0.kind == $1.kind && $0.rawLine == $1.rawLine && $0.text == $1.text }
    }

    /// Indices into the real diff's lines of every changed line in one hunk.
    func changedLineIndices(inHunk hunk: Int) -> Set<Int> {
        var result: Set<Int> = []
        for (index, line) in lines.enumerated() where line.hunkIndex == hunk && line.isChange {
            if let real = realIndex(ofRow: index) { result.insert(real) }
        }
        return result
    }

    /// highlight.js language id inferred from `path`, or `nil` when unknown.
    var languageHint: String? { SyntaxLanguage.forPath(path) }

    /// Counted from the parsed lines rather than asked of git again: the diff
    /// is already here, and `git show --numstat` would be a second round trip
    /// for something this file can answer itself.
    var addedLineCount: Int { lines.count { $0.kind == .addition } }

    var removedLineCount: Int { lines.count { $0.kind == .deletion } }
}
