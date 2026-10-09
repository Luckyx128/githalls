//
//  ClockifyModels.swift
//  GitHalls
//

import Foundation

struct ClockifyUser: Equatable {
    let id: String
    let name: String
    let activeWorkspaceID: String?
}

struct ClockifyWorkspace: Identifiable, Hashable {
    let id: String
    let name: String
}

struct ClockifyProject: Identifiable, Hashable {
    let id: String
    let name: String
    let clientName: String?

    /// How the picker shows it: "SIGRA WEB" or "SIGRA WEB · Client".
    var label: String { clientName.map { "\(name) · \($0)" } ?? name }
}

struct ClockifyTask: Identifiable, Hashable {
    let id: String
    let name: String
}

struct ClockifyTag: Identifiable, Hashable {
    let id: String
    let name: String
}

/// One time entry as Clockify answers it. A nil `end` is a running timer.
struct ClockifyTimeEntry: Identifiable, Equatable {
    let id: String
    let description: String
    let projectID: String?
    let taskID: String?
    let tagIDs: [String]
    let start: Date
    let end: Date?

    var isRunning: Bool { end == nil }
}

/// What a write sends. Leaving `end` out starts a timer instead of logging time.
struct ClockifyNewEntry: Equatable {
    var description: String
    var projectID: String?
    var taskID: String?
    var tagIDs: [String] = []
    var start: Date
    var end: Date?
}

enum ClockifyError: LocalizedError {
    case unauthorized
    case http(status: Int, message: String?)
    case malformedResponse
    case notConnected

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Clockify rejected the API key."
        case .http(let status, let message):
            message ?? "Clockify responded with \(status)."
        case .malformedResponse:
            "Clockify response was in an unexpected format."
        case .notConnected:
            "Clockify is not connected yet. Add your API key in Settings › Clockify."
        }
    }
}
