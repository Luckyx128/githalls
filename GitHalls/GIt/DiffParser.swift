//
//  DiffParser.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation

enum DiffParser {
    static func parse(_ raw: String) -> FileDiff {
        guard !raw.isEmpty else {
            return FileDiff(path: "", lines: [])
        }
        
        var lines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0
        var path = ""

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if rawLine.hasPrefix("+++ b/") {
                path = String(rawLine.dropFirst(6))
                continue
            }
            if rawLine.hasPrefix("diff --git") || rawLine.hasPrefix("index ") || rawLine.hasPrefix("--- ") {
                continue
            }

            if rawLine.hasPrefix("@@") {
                let pieces = rawLine.split(separator: "@@")
                let body = pieces.first ?? ""                // " -12,7 +12,8 "
                let parts = body.split(separator: " ")        // ["-12,7", "+12,8"]
                oldLine = Int(parts[0].dropFirst().split(separator: ",")[0]) ?? 0
                newLine = Int(parts[1].dropFirst().split(separator: ",")[0]) ?? 0

                // depois do segundo "@@", o git às vezes inclui o nome da função/escopo do hunk
                let trailingContext = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespaces) : ""
                let label = trailingContext.isEmpty ? "Line \(newLine)" : "Line \(newLine) · \(trailingContext)"

                lines.append(DiffLine(kind: .hunkHeader, text: label, oldLineNumber: nil, newLineNumber: nil))
                continue
            }

            switch rawLine.first {
            case "+":
                lines.append(DiffLine(kind: .addition, text: String(rawLine.dropFirst()), oldLineNumber: nil, newLineNumber: newLine))
                newLine += 1
            case "-":
                lines.append(DiffLine(kind: .deletion, text: String(rawLine.dropFirst()), oldLineNumber: oldLine, newLineNumber: nil))
                oldLine += 1
            default:
                lines.append(DiffLine(kind: .context, text: String(rawLine.dropFirst()), oldLineNumber: oldLine, newLineNumber: newLine))
                oldLine += 1
                newLine += 1
            }
        }
        return FileDiff(path: path, lines: lines)
    }

    static func syntheticAllAdditions(path: String, content: String) -> FileDiff {
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { DiffLine(kind: .addition, text: String($0.element), oldLineNumber: nil, newLineNumber: $0.offset + 1) }
        return FileDiff(path: path, lines: lines)
    }
}
