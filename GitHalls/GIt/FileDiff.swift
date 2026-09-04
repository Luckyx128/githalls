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

    /// highlight.js language id inferred from `path`, or `nil` when unknown.
    var languageHint: String? { SyntaxLanguage.forPath(path) }
}
