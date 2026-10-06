//
//  CommitMessageComposer.swift
//  GitHalls
//

import Foundation

/// Someone credited with a `Co-authored-by:` trailer.
struct CoAuthor: Hashable, Identifiable {
    let name: String
    let email: String

    var id: String { email.lowercased() }

    /// The form git and GitHub read: `Name <email>`.
    var display: String { "\(name) <\(email)>" }

    var trailer: String { "Co-authored-by: \(display)" }

    /// `Name <email>` or nothing. A trailer without an address credits no one on
    /// GitHub, so a bare name is rejected instead of being committed silently.
    static func parse(_ raw: String) -> CoAuthor? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasSuffix(">"), let open = text.lastIndex(of: "<") else { return nil }
        let name = text[..<open].trimmingCharacters(in: .whitespaces)
        let email = text[text.index(after: open)..<text.index(before: text.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !email.isEmpty,
              !email.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" }),
              let at = email.firstIndex(of: "@"),
              at != email.startIndex,
              email.index(after: at) != email.endIndex,
              !name.contains(where: { $0 == "<" || $0 == ">" })
        else { return nil }
        return CoAuthor(name: name, email: email)
    }
}

/// Builds the message git is given, and takes one apart again.
///
/// The form has three fields (summary, description, co-authors) but git has one
/// message. Keeping both directions here means "undo" and "amend" put back
/// exactly what "commit" wrote.
enum CommitMessageComposer {
    private static let trailerKey = "co-authored-by:"

    /// Summary plus a body that is the description followed, after a blank line,
    /// by one trailer per co-author. A person already named in the description is
    /// not added twice. The body is nil when there is nothing to say beyond the
    /// summary, so the caller passes no empty `-m`.
    static func compose(
        summary: String,
        description: String,
        coAuthors: [CoAuthor]
    ) -> (summary: String, body: String?) {
        let subject = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = description.trimmingCharacters(in: .whitespacesAndNewlines)

        var present = Set(trailerAuthors(in: body).map(\.id))
        var added: [String] = []
        for author in coAuthors where present.insert(author.id).inserted {
            added.append(author.trailer)
        }

        var paragraphs: [String] = []
        if !body.isEmpty { paragraphs.append(body) }
        if !added.isEmpty { paragraphs.append(added.joined(separator: "\n")) }
        return (subject, paragraphs.isEmpty ? nil : paragraphs.joined(separator: "\n\n"))
    }

    /// The inverse of `compose`: trailers leave the description and come back as
    /// co-authors, so the form does not show them twice.
    static func split(_ message: String) -> (summary: String, description: String, coAuthors: [CoAuthor]) {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return ("", "", [])
        }

        var seen = Set<String>()
        var coAuthors: [CoAuthor] = []
        var rest: [String] = []
        for line in lines[lines.index(after: first)...] {
            if let author = trailerAuthor(in: line) {
                if seen.insert(author.id).inserted { coAuthors.append(author) }
            } else {
                rest.append(line)
            }
        }

        return (
            lines[first].trimmingCharacters(in: .whitespaces),
            rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            coAuthors
        )
    }

    private static func trailerAuthors(in text: String) -> [CoAuthor] {
        text.split(separator: "\n").compactMap { trailerAuthor(in: String($0)) }
    }

    private static func trailerAuthor(in line: String) -> CoAuthor? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix(trailerKey) else { return nil }
        return CoAuthor.parse(String(trimmed.dropFirst(trailerKey.count)))
    }

    /// Distinct people from `Name <email>` lines, first occurrence wins (the log
    /// is newest first, so that is the spelling they use now). Same address in a
    /// different case is the same person.
    static func uniqueAuthors(_ lines: [String]) -> [CoAuthor] {
        var seen = Set<String>()
        return lines.compactMap(CoAuthor.parse).filter { seen.insert($0.id).inserted }
    }
}
