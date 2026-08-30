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
        var insideHunk = false

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            // "diff --git a/x b/y" existe sempre, mesmo quando não há "+++ b/" depois
            // (arquivo deletado usa "+++ /dev/null", binário/rename puro não tem "+++" nenhum) —
            // usa como base pro path, "+++ b/" abaixo sobrescreve com o valor mais preciso quando existir.
            if rawLine.hasPrefix("diff --git a/") {
                let rest = rawLine.dropFirst("diff --git a/".count)
                if let range = rest.range(of: " b/") {
                    path = String(rest[range.upperBound...])
                }
                continue
            }

            if rawLine.hasPrefix("+++ b/") {
                path = String(rawLine.dropFirst(6))
                continue
            }

            if rawLine.hasPrefix("Binary files ") && rawLine.hasSuffix(" differ") {
                lines.append(DiffLine(kind: .hunkHeader, text: "Binary file not shown", oldLineNumber: nil, newLineNumber: nil))
                return FileDiff(path: path, lines: lines)
            }

            // Diff de merge commit ("@@@ -a,b -c,d +e,f @@@") usa um formato combinado
            // (múltiplos "@@", prefixo de várias letras por linha) que este parser não entende —
            // melhor avisar do que tentar parsear e corromper o conteúdo.
            if rawLine.hasPrefix("@@@") {
                lines.append(DiffLine(kind: .hunkHeader, text: "Merge diff not supported", oldLineNumber: nil, newLineNumber: nil))
                return FileDiff(path: path, lines: lines)
            }

            if rawLine.hasPrefix("@@") {
                let pieces = rawLine.split(separator: "@@")
                let body = pieces.first ?? ""
                let parts = body.split(separator: " ")
                oldLine = Int(parts[0].dropFirst().split(separator: ",")[0]) ?? 0
                newLine = Int(parts[1].dropFirst().split(separator: ",")[0]) ?? 0

                let trailingContext = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespaces) : ""
                let label = trailingContext.isEmpty ? "Line \(newLine)" : "Line \(newLine) · \(trailingContext)"

                lines.append(DiffLine(kind: .hunkHeader, text: label, oldLineNumber: nil, newLineNumber: nil))
                insideHunk = true
                continue
            }

            // Qualquer coisa antes do primeiro "@@" é cabeçalho estendido do git
            // (index, ---, new/deleted file mode, rename from/to, similarity index...) — ignora.
            guard insideHunk else { continue }

            // "\ No newline at end of file" — marcador do git, não é conteúdo real do arquivo.
            if rawLine.hasPrefix("\\") { continue }

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

        if lines.isEmpty {
            // Path mudou de mode/foi renomeado sem alteração de conteúdo — não é "sem diff nenhum".
            lines.append(DiffLine(kind: .hunkHeader, text: "No content changes", oldLineNumber: nil, newLineNumber: nil))
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
