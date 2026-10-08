//
//  PatchBuilder.swift
//  GitHalls
//
//  Turns a chosen subset of the changed lines of ONE file's diff into a patch
//  `git apply` accepts — the engine behind staging, unstaging and discarding
//  single lines and hunks.
//

import Foundation

enum PatchBuilder {
    /// Which way `git apply` will run the patch.
    enum Direction {
        /// Staging: apply the unstaged diff to the index. A `-` line that is
        /// not selected is still in the file, so it turns into context; a `+`
        /// line that is not selected does not exist yet, so it is dropped.
        case forward
        /// Unstaging or discarding: apply with `--reverse`. Mirror image — an
        /// unselected `+` is in the file and stays as context, an unselected
        /// `-` is not there and is dropped.
        case reverse
    }

    /// `selected` holds indices into `diff.lines`; anything that is not a
    /// `+`/`-` line (context, headers) is ignored. Returns nil when nothing
    /// selectable remains, or for a diff that cannot be patched.
    static func build(diff: FileDiff, selected: Set<Int>, direction: Direction) -> String? {
        guard !diff.isBinary, !diff.patchHeader.isEmpty else { return nil }

        var body: [String] = []
        // How far the far side of the patch has drifted from the anchor side
        // because of earlier hunks that were emitted shorter or longer.
        var drift = 0

        let hunkCount = diff.hunkCount
        guard hunkCount > 0 else { return nil }

        // Group line indices by hunk once, keeping order.
        var hunks: [[Int]] = Array(repeating: [], count: hunkCount)
        var headers: [Int?] = Array(repeating: nil, count: hunkCount)
        for (index, line) in diff.lines.enumerated() {
            guard let hunk = line.hunkIndex else { continue }
            if line.kind == .hunkHeader { headers[hunk] = index } else { hunks[hunk].append(index) }
        }

        for hunk in 0..<hunkCount {
            guard let headerIndex = headers[hunk],
                  let range = diff.lines[headerIndex].hunkRange,
                  hunks[hunk].contains(where: { selected.contains($0) && diff.lines[$0].isChange })
            else { continue }

            var out: [String] = []
            var oldCount = 0
            var newCount = 0

            for index in hunks[hunk] {
                let line = diff.lines[index]
                guard let raw = line.rawLine else { return nil }
                let isSelected = selected.contains(index)
                let content = String(raw.dropFirst())

                switch line.kind {
                case .context:
                    out.append(raw)
                    oldCount += 1; newCount += 1
                case .addition:
                    if isSelected {
                        out.append(raw); newCount += 1
                    } else if direction == .reverse {
                        out.append(" " + content); oldCount += 1; newCount += 1
                    } else {
                        continue  // dropped, and its marker with it
                    }
                case .deletion:
                    if isSelected {
                        out.append(raw); oldCount += 1
                    } else if direction == .forward {
                        out.append(" " + content); oldCount += 1; newCount += 1
                    } else {
                        continue
                    }
                case .hunkHeader, .expander:
                    continue
                }
                if line.noNewlineAtEnd { out.append(DiffParser.noNewlineMarker) }
            }

            // The side git will search by keeps the header's own start. The
            // other side is derived from it, which is only exact when counted
            // through the hunks already emitted.
            let anchorStart = direction == .forward ? range.oldStart : range.newStart
            let anchorCount = direction == .forward ? oldCount : newCount
            let farCount = direction == .forward ? newCount : oldCount

            var farStart = (anchorCount == 0 ? anchorStart + 1 : anchorStart) + drift
            if farCount == 0 { farStart -= 1 }
            drift += farCount - anchorCount

            let oldStart = direction == .forward ? anchorStart : farStart
            let newStart = direction == .forward ? farStart : anchorStart

            body.append("@@ -\(format(oldStart, oldCount)) +\(format(newStart, newCount)) @@")
            body.append(contentsOf: out)
        }

        guard !body.isEmpty else { return nil }
        return (diff.patchHeader + body).joined(separator: "\n") + "\n"
    }

    /// Every changed line of the diff.
    static func allChanged(in diff: FileDiff) -> Set<Int> {
        Set(diff.lines.indices.filter { diff.lines[$0].isChange })
    }

    private static func format(_ start: Int, _ count: Int) -> String {
        count == 1 ? "\(start)" : "\(start),\(count)"
    }
}
