//
//  DiffParser.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation

enum DiffParser {
    static let noNewlineMarker = "\\ No newline at end of file"

    /// Splits on `\n` only. `String.split(separator: "\n")` treats "\r\n" as a
    /// single Character that is not "\n", so a CRLF file would never split.
    static func splitLines(_ raw: String) -> [String] {
        var pieces = raw.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)) }
        // The newline that ends the last line is a terminator, not a blank line.
        if raw.unicodeScalars.last == "\n", pieces.last == "" { pieces.removeLast() }
        return pieces
    }

    private static func displayText(_ raw: Substring) -> String {
        var text = String(raw.dropFirst())
        if text.unicodeScalars.last == "\r" { text.unicodeScalars.removeLast() }
        return text
    }

    /// `-12,3` / `+4` → (12, 3) / (4, 1).
    private static func rangePart(_ part: Substring) -> (start: Int, count: Int)? {
        let pieces = part.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard let start = pieces.first.flatMap({ Int($0) }) else { return nil }
        let count = pieces.count > 1 ? (Int(pieces[1]) ?? 1) : 1
        return (start, count)
    }

    static func parse(_ raw: String) -> FileDiff {
        guard !raw.isEmpty else {
            return FileDiff(path: "", lines: [])
        }

        var lines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0
        var path = ""
        var insideHunk = false
        var hunkIndex = -1
        var header: [String] = []
        var isNew = false
        var isDeleted = false
        var isRename = false

        for rawString in splitLines(raw) {
            let rawLine = Substring(rawString)

            // "diff --git a/x b/y" existe sempre, mesmo quando não há "+++ b/" depois
            // (arquivo deletado usa "+++ /dev/null", binário/rename puro não tem "+++" nenhum) —
            // usa como base pro path, "+++ b/" abaixo sobrescreve com o valor mais preciso quando existir.
            if !insideHunk {
                if rawLine.hasPrefix("diff --git a/") {
                    let rest = rawLine.dropFirst("diff --git a/".count)
                    if let range = rest.range(of: " b/") {
                        path = String(rest[range.upperBound...])
                    }
                    header.append(rawString)
                    continue
                }

                if rawLine.hasPrefix("+++ b/") {
                    path = String(rawLine.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "\t"))
                    header.append(rawString)
                    continue
                }

                if rawLine.hasPrefix("--- ") || rawLine.hasPrefix("+++ ") {
                    header.append(rawString)
                    continue
                }
                if rawLine.hasPrefix("new file mode") { isNew = true; header.append(rawString); continue }
                if rawLine.hasPrefix("deleted file mode") { isDeleted = true; header.append(rawString); continue }
                if rawLine.hasPrefix("rename from") || rawLine.hasPrefix("rename to") || rawLine.hasPrefix("copy from") {
                    isRename = true
                }
            }

            if rawLine.hasPrefix("Binary files ") && rawLine.hasSuffix(" differ") {
                lines.append(DiffLine(kind: .hunkHeader, text: "Binary file not shown", oldLineNumber: nil, newLineNumber: nil))
                return FileDiff(path: path, lines: lines, isBinary: true)
            }

            // Diff de merge commit ("@@@ -a,b -c,d +e,f @@@") usa um formato combinado
            // (múltiplos "@@", prefixo de várias letras por linha) que este parser não entende —
            // melhor avisar do que tentar parsear e corromper o conteúdo.
            if rawLine.hasPrefix("@@@") {
                lines.append(DiffLine(kind: .hunkHeader, text: "Merge diff not supported", oldLineNumber: nil, newLineNumber: nil))
                return FileDiff(path: path, lines: lines)
            }

            if rawLine.hasPrefix("@@") {
                let body = rawLine.dropFirst(2)
                let closing = body.range(of: "@@")
                let numbers = (closing.map { body[..<$0.lowerBound] } ?? body).split(separator: " ")
                let old = numbers.count > 0 ? rangePart(numbers[0]) : nil
                let new = numbers.count > 1 ? rangePart(numbers[1]) : nil
                oldLine = old?.start ?? 0
                newLine = new?.start ?? 0

                let trailingContext = closing.map { String(body[$0.upperBound...]).trimmingCharacters(in: .whitespaces) } ?? ""
                let label = trailingContext.isEmpty ? "Line \(newLine)" : "Line \(newLine) · \(trailingContext)"

                hunkIndex += 1
                var headerLine = DiffLine(kind: .hunkHeader, text: label, oldLineNumber: nil, newLineNumber: nil)
                headerLine.rawLine = rawString
                headerLine.hunkIndex = hunkIndex
                headerLine.hunkRange = HunkRange(oldStart: old?.start ?? 0, oldCount: old?.count ?? 1,
                                                 newStart: new?.start ?? 0, newCount: new?.count ?? 1)
                lines.append(headerLine)
                insideHunk = true
                continue
            }

            // Qualquer coisa antes do primeiro "@@" é cabeçalho estendido do git
            // (index, ---, new/deleted file mode, rename from/to, similarity index...) — ignora.
            guard insideHunk else { continue }

            // "\ No newline at end of file" — marcador do git, não é conteúdo real do arquivo.
            // Fica gravado na linha que ele segue, para o patch poder reproduzi-lo.
            if rawLine.hasPrefix("\\") {
                if !lines.isEmpty { lines[lines.count - 1].noNewlineAtEnd = true }
                continue
            }

            var line: DiffLine
            switch rawLine.first {
            case "+":
                line = DiffLine(kind: .addition, text: displayText(rawLine), oldLineNumber: nil, newLineNumber: newLine)
                newLine += 1
            case "-":
                line = DiffLine(kind: .deletion, text: displayText(rawLine), oldLineNumber: oldLine, newLineNumber: nil)
                oldLine += 1
            default:
                line = DiffLine(kind: .context, text: displayText(rawLine), oldLineNumber: oldLine, newLineNumber: newLine)
                oldLine += 1
                newLine += 1
            }
            line.rawLine = rawString
            line.hunkIndex = hunkIndex
            lines.append(line)
        }

        if lines.isEmpty {
            // Path mudou de mode/foi renomeado sem alteração de conteúdo — não é "sem diff nenhum".
            lines.append(DiffLine(kind: .hunkHeader, text: "No content changes", oldLineNumber: nil, newLineNumber: nil))
        }
        var diff = FileDiff(path: path, lines: lines)
        diff.patchHeader = header
        diff.isNewFile = isNew
        diff.isDeletedFile = isDeleted
        diff.isRename = isRename
        return diff
    }

    /// An untracked file shown as the diff git would print once it was added,
    /// down to the raw lines, so a subset of it can be staged as a new-file patch.
    static func syntheticAllAdditions(path: String, content: String) -> FileDiff {
        let pieces = splitLines(content)
        let endsWithNewline = content.unicodeScalars.last == "\n"

        var lines: [DiffLine] = []
        guard !pieces.isEmpty else {
            var diff = FileDiff(path: path, lines: [])
            diff.isNewFile = true
            return diff
        }

        var header = DiffLine(kind: .hunkHeader, text: "Line 1", oldLineNumber: nil, newLineNumber: nil)
        header.rawLine = "@@ -0,0 +1,\(pieces.count) @@"
        header.hunkIndex = 0
        header.hunkRange = HunkRange(oldStart: 0, oldCount: 0, newStart: 1, newCount: pieces.count)
        lines.append(header)

        for (offset, piece) in pieces.enumerated() {
            var text = piece
            if text.unicodeScalars.last == "\r" { text.unicodeScalars.removeLast() }
            var line = DiffLine(kind: .addition, text: text, oldLineNumber: nil, newLineNumber: offset + 1)
            line.rawLine = "+" + piece
            line.hunkIndex = 0
            line.noNewlineAtEnd = offset == pieces.count - 1 && !endsWithNewline
            lines.append(line)
        }

        var diff = FileDiff(path: path, lines: lines)
        let name = path.contains(" ") ? path + "\t" : path
        diff.patchHeader = ["diff --git a/\(path) b/\(path)", "new file mode 100644", "--- /dev/null", "+++ b/\(name)"]
        diff.isNewFile = true
        return diff
    }
}
