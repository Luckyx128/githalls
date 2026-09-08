//
//  JiraWorkflowTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct JiraWorkflowTests {
    private func transition(_ name: String, _ status: String, _ category: String) -> JiraTransition {
        JiraTransition(id: "1", name: name, toStatus: status, toStatusCategory: category)
    }

    @Test func picksTheOnlyMoveIntoAnInProgressStatus() {
        let transitions = [
            transition("Done", "Done", "done"),
            transition("Begin", "In Development", "indeterminate")
        ]

        #expect(JiraWorkflow.startWork(from: transitions, currentStatusCategory: "new")
                == .move(transitions[1]))
    }

    @Test func prefersTheOneNamedLikeStartingWorkWhenSeveralQualify() {
        let transitions = [
            transition("Send to review", "In Review", "indeterminate"),
            transition("Start progress", "In Progress", "indeterminate")
        ]

        #expect(JiraWorkflow.startWork(from: transitions, currentStatusCategory: "new")
                == .move(transitions[1]))
    }

    @Test func recognisesThePortugueseNameToo() {
        let transitions = [
            transition("Enviar para revisão", "Em Revisão", "indeterminate"),
            transition("Iniciar", "Em Andamento", "indeterminate")
        ]

        #expect(JiraWorkflow.startWork(from: transitions, currentStatusCategory: "new")
                == .move(transitions[1]))
    }

    @Test func fallsBackToWorkflowOrderWhenNothingElseDecides() {
        let transitions = [
            transition("Triage", "Triaged", "indeterminate"),
            transition("Escalate", "Escalated", "indeterminate")
        ]

        #expect(JiraWorkflow.startWork(from: transitions, currentStatusCategory: "new")
                == .move(transitions[0]))
    }

    @Test func saysTheIssueIsAlreadyInProgressRatherThanMovingItAgain() {
        let transitions = [transition("Restart", "In Progress", "indeterminate")]

        #expect(JiraWorkflow.startWork(from: transitions, currentStatusCategory: "indeterminate")
                == .alreadyInProgress)
    }

    @Test func saysThereIsNoCandidateWhenTheWorkflowOffersNone() {
        let transitions = [transition("Close", "Done", "done")]

        #expect(JiraWorkflow.startWork(from: transitions, currentStatusCategory: "new") == .noCandidate)
    }

    @Test func saysThereIsNoCandidateWhenTheWorkflowIsEmpty() {
        #expect(JiraWorkflow.startWork(from: [], currentStatusCategory: "new") == .noCandidate)
    }

    @Test func labelNamesTheTargetStatusBecauseThatIsTheColumnPeopleSee() {
        let move = transition("Start progress", "In Progress", "indeterminate")
        let all = [move, transition("Close", "Done", "done")]

        #expect(JiraWorkflow.label(for: move, among: all) == "In Progress")
    }

    @Test func labelAddsTheTransitionNameWhenTwoMovesLandOnTheSameStatus() {
        let reopen = transition("Reopen", "To Do", "new")
        let all = [reopen, transition("Send back", "To Do", "new")]

        #expect(JiraWorkflow.label(for: reopen, among: all) == "To Do (Reopen)")
    }
}
