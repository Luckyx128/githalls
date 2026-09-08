//
//  FileDiff.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation

struct DiffLine: Identifiable {
    enum Kind: Hashable {
        case addition, deletion, context, hunkHeader
    }

    let id = UUID()
    let kind: Kind
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

struct FileDiff {
    let path: String
    let lines: [DiffLine]

    /// git had no text to diff. The lines then hold a notice and nothing else,
    /// and what the file actually is — an image, or something to open elsewhere
    /// — is decided from the path by `FilePreview`.
    var isBinary = false

    /// highlight.js language id inferred from `path`, or `nil` when unknown.
    var languageHint: String? { SyntaxLanguage.forPath(path) }
}
