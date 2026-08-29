//
//  SyntaxHighlighter.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 29/08/26.
//

import Foundation
import SwiftUI

enum SyntaxHighlighter {
    private static let keywords: Set<String> = [
        // Swift
        "func", "class", "struct", "enum", "protocol", "extension", "import",
        "var", "let", "if", "else", "guard", "return", "for", "while", "switch",
        "case", "default", "break", "continue", "in", "as", "is", "try", "catch",
        "throw", "throws", "async", "await", "public", "private", "internal",
        "static", "final", "override", "self", "super", "nil", "true", "false",
        // C-like / JS / Python (bem sobreposto de propósito, é genérico)
        "def", "elif", "None", "True", "False", "from", "function", "const",
        "export", "new", "this", "void", "int", "string", "bool", "null",
        "interface", "namespace", "typedef", "package"
    ]

    private static let lineCommentMarkers = ["//", "#"]

    static func highlight(_ line: String) -> AttributedString {
        var result = AttributedString()
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            if let marker = lineCommentMarkers.first(where: { matches(chars, at: i, marker: $0) }) {
                _ = marker
                result += colored(String(chars[i...]), .green)
                break
            }

            let char = chars[i]

            if char == "\"" || char == "'" {
                let quote = char
                var j = i + 1
                while j < chars.count && chars[j] != quote { j += 1 }
                let end = min(j + 1, chars.count)
                result += colored(String(chars[i..<end]), .red)
                i = end
                continue
            }

            if char.isNumber {
                var j = i
                while j < chars.count && (chars[j].isNumber || chars[j] == ".") { j += 1 }
                result += colored(String(chars[i..<j]), .orange)
                i = j
                continue
            }

            if char.isLetter || char == "_" {
                var j = i
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") { j += 1 }
                let word = String(chars[i..<j])
                result += keywords.contains(word) ? colored(word, .pink) : AttributedString(word)
                i = j
                continue
            }

            result += AttributedString(String(char))
            i += 1
        }

        return result
    }

    private static func matches(_ chars: [Character], at index: Int, marker: String) -> Bool {
        let markerChars = Array(marker)
        guard index + markerChars.count <= chars.count else { return false }
        return Array(chars[index..<index + markerChars.count]) == markerChars
    }

    private static func colored(_ text: String, _ color: Color) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = color
        return attr
    }
}
