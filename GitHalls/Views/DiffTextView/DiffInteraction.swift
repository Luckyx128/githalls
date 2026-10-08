//
//  DiffInteraction.swift
//  GitHalls
//
//  What the Changes diff can do beyond showing text: hunk buttons and line
//  selection for partial staging. History diffs pass none of this.
//

import Foundation
import Observation

/// The set of changed lines the user has picked in the gutter. Indices point
/// into `FileDiff.lines`, so it only means something for the diff it was made
/// on — whoever replaces the diff clears it.
@MainActor
@Observable
final class DiffSelection {
    private(set) var lines: Set<Int> = []

    /// Where ⇧-click extends from.
    @ObservationIgnored var anchor: Int?

    /// The text view repaints itself through this; SwiftUI watches `lines`.
    @ObservationIgnored var onChange: (() -> Void)?

    func set(_ new: Set<Int>) {
        guard new != lines else { return }
        lines = new
        onChange?()
    }

    func clear() {
        anchor = nil
        set([])
    }
}

/// How much of partial staging the shown diff supports.
enum DiffPartialMode: Equatable {
    /// Hunk buttons and line selection.
    case lines
    /// A new or deleted file: its single hunk is the whole file, and splitting
    /// it would leave git with a half-created file. Hunk buttons act on the file.
    case wholeFile
}

struct DiffInteraction {
    let side: DiffSide
    let mode: DiffPartialMode
    let selection: DiffSelection
    /// Discarding is not offered for a file git does not know yet.
    let canDiscard: Bool
    /// Same value for the same file and side, so a reload keeps the scroll.
    let identity: String

    /// The argument is the index of the hunk header line in `FileDiff.lines`.
    let onStageHunk: (Int) -> Void
    let onUnstageHunk: (Int) -> Void
    let onDiscardHunk: (Int) -> Void
}

extension FileDiff {
    /// What partial staging can do with this diff, or nil when nothing.
    func partialMode(for change: FileChange, side: DiffSide) -> DiffPartialMode? {
        guard !isBinary, !isRename, change.status != .unmerged, hunkCount > 0,
              !patchHeader.isEmpty
        else { return nil }
        if isDeletedFile { return .wholeFile }
        if isNewFile && side == .staged { return .wholeFile }
        return .lines
    }
}
