//
//  JiraBranchName.swift
//  GitHalls
//

import Foundation

/// The word a branch name starts with, read off the issue type: "feature",
/// "fix" or "chore".
///
/// Deliberately not `ConventionalCommitType`. That list spells the type "feat"
/// because the Conventional Commits spec requires it in a commit subject —
/// changing that string to suit a branch name would change every message the
/// app writes. The two vocabularies also differ in size and purpose: eleven
/// entries to help someone word a commit, three words to say what a branch is
/// for.
enum JiraBranchType {
    static let feature = "feature"
    static let fix = "fix"
    static let chore = "chore"

    /// Keys are already folded — `JiraText.fold` is what looks them up.
    private static let byType: [String: String] = [
        "bug": fix,
        "bugfix": fix,
        "defect": fix,
        "defeito": fix,
        "erro": fix,
        "falha": fix,
        "incident": fix,
        "incidente": fix,
        "problema": fix,

        "story": feature,
        "historia": feature,
        "estoria": feature,
        "epic": feature,
        "epico": feature,
        "new feature": feature,
        "feature": feature,
        "funcionalidade": feature,
        "nova funcionalidade": feature,
        "improvement": feature,
        "enhancement": feature,
        "melhoria": feature,

        "task": chore,
        "tarefa": chore,
        "sub-task": chore,
        "subtask": chore,
        "subtarefa": chore,
        "sub-tarefa": chore,
        "chore": chore,
        "manutencao": chore
    ]

    private static let wordSeparators = CharacterSet(charactersIn: " -_/\\.,:;()[]")

    static func of(_ issue: JiraIssue) -> String { of(issue.type) }

    static func of(_ jiraType: String?) -> String {
        let folded = JiraText.fold(jiraType)
        guard !folded.isEmpty else { return feature }

        if let exact = byType[folded] { return exact }

        // A project is free to invent "Bug de Produção" or "Story - Frontend",
        // so the words are tried one at a time. By word and not by substring:
        // "Debug tooling" contains "bug" and is not a bug.
        for word in folded.components(separatedBy: wordSeparators) where !word.isEmpty {
            if let byWord = byType[word] { return byWord }
        }

        return feature
    }
}

/// The branch name an issue suggests: "feature-SWEB-12903" — what the branch is
/// for, then the card it belongs to.
///
/// The summary is deliberately not part of it. A branch is looked up by its
/// card, and the key is what people say out loud; a slug of the title only made
/// the name longer and turned every rename of the card into a name that no
/// longer matched. A suggestion, not a rule — the user edits it before anything
/// is created.
enum JiraBranchName {
    static func suggest(for issue: JiraIssue) -> String {
        suggest(key: issue.key, jiraType: issue.type)
    }

    static func suggest(key: String, jiraType: String?) -> String {
        let type = JiraBranchType.of(jiraType)
        let sanitized = sanitize(key)

        return sanitized.isEmpty ? type : "\(type)-\(sanitized)"
    }

    /// Keeps the key exactly as Jira spells it, upper case included, and
    /// collapses anything git would refuse into a single dash.
    private static func sanitize(_ key: String) -> String {
        var result = ""

        for character in key.trimmingCharacters(in: .whitespaces) {
            if (character.isASCII && (character.isLetter || character.isNumber))
                || character == "_" || character == "-" {
                result.append(character)
            } else if let last = result.last, last != "-" {
                result.append("-")
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
