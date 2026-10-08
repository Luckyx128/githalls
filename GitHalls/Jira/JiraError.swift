//
//  JiraError.swift
//  GitHalls
//

import Foundation

enum JiraError: LocalizedError {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case http(status: Int, message: String?)

    /// Jira's per-field validation, keyed by field id: `{"errors":{"description":"Description is required."}}`.
    case fieldErrors([String: String])
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Jira rejected the credentials."
        case .rateLimited:
            "Jira asked to slow down (rate limited)."
        case .http(let status, let message):
            message ?? "Jira responded with \(status)."
        case .fieldErrors(let errors):
            errors.sorted { $0.key < $1.key }.map(\.value).joined(separator: " ")
        case .malformedResponse:
            "Jira response was in an unexpected format."
        }
    }
}
