//
//  JiraWorkflow.swift
//  GitHalls
//

import Foundation

/// Which move starts work, once the workflow has been asked.
enum JiraStartWork: Equatable {
    case move(JiraTransition)

    /// The issue is already in progress. Not an error, and not something to
    /// move again.
    case alreadyInProgress

    /// This workflow offers no move into an in-progress status from where the
    /// issue stands.
    case noCandidate
}

/// The decisions a board makes about a project's workflow, kept out of the
/// views because they are the part worth testing.
enum JiraWorkflow {
    /// Words a workflow uses for the move that starts work. Only ever a
    /// tie-breaker: the status category has already narrowed the field, and a
    /// project that names nothing recognisably still gets an answer.
    private static let startingWords = [
        "in progress", "progress", "start", "doing", "development",
        "andamento", "iniciar", "desenvolvimento", "execucao", "fazendo"
    ]

    /// Status names belong to the project; the category does not, so that is
    /// what decides which moves qualify at all.
    static func startWork(from transitions: [JiraTransition], currentStatusCategory: String) -> JiraStartWork {
        // Moving an issue that is already in progress is not what the button
        // promises, and doing it silently would be worse than doing nothing.
        guard currentStatusCategory != "indeterminate" else { return .alreadyInProgress }

        let candidates = transitions.filter(\.leadsToInProgress)
        guard let first = candidates.first else { return .noCandidate }
        guard candidates.count > 1 else { return .move(first) }

        if let named = candidates.first(where: namedLikeStartingWork) { return .move(named) }

        // Jira lists transitions in workflow order, so the first is the one the
        // workflow itself puts first. No prompt: a button that stops to ask
        // which of three moves you meant is no longer a one-click button, and
        // the result is named afterwards and one right-click from correction.
        return .move(first)
    }

    private static func namedLikeStartingWork(_ transition: JiraTransition) -> Bool {
        let name = JiraText.fold(transition.name)
        let status = JiraText.fold(transition.toStatus)

        return startingWords.contains { name.contains($0) || status.contains($0) }
    }

    /// What a menu item says. The target status, because that is the column the
    /// person is looking at — unless two moves land on the same one, when the
    /// transition's own name is the only thing telling them apart.
    static func label(for transition: JiraTransition, among all: [JiraTransition]) -> String {
        let ambiguous = all.filter { $0.toStatus == transition.toStatus }.count > 1

        return ambiguous ? "\(transition.toStatus) (\(transition.name))" : transition.toStatus
    }
}

/// What starting work actually managed to do. A refusal is `.failed`, and the
/// view model's `actionMessage` says why — a partial success is worth stating
/// plainly rather than hiding behind an error.
enum JiraStartWorkOutcome: Equatable {
    case moved(to: String)
    case alreadyInProgress
    case noCandidate
    case failed
}
