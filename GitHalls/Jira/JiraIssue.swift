//
//  JiraIssue.swift
//  GitHalls
//

import Foundation
struct JiraIssue: Identifiable, Equatable {
    let key: String
    let summary: String
    let status: String
    let statusCategory: String
    let type: String
    let priority: String?
    let updated: Date

    var id: String { key }
}
