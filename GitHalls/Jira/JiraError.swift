//
//  JiraError.swift
//  GitHalls
//

import Foundation

enum JiraError: LocalizedError {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case http(status: Int, message: String?)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Jira rejected the credentials."
        case .rateLimited:
            "Jira asked to slow down (rate limited)."
        case .http(let status, let message):
            message ?? "Jira responded with \(status)."
        case .malformedResponse:
            "Jira response was in an unexpected format."
        }
    }
}
