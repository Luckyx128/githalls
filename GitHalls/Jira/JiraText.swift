//
//  JiraText.swift
//  GitHalls
//

import Foundation

/// Folding for text a Jira project names freely: issue types and status names
/// arrive in whatever language and casing an admin typed, so nothing that has
/// to recognise them can compare them as they came.
enum JiraText {
    /// Lower case, accents removed, inner whitespace collapsed to one space.
    /// "Histórias  de Usuário" and "historia de usuario" have to answer the
    /// same question, and no locale-aware comparison does that for free.
    static func fold(_ value: String?) -> String {
        guard let value else { return "" }

        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))

        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
