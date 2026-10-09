//
//  ClockifyCredentials.swift
//  GitHalls
//

import Foundation
import Security

/// What is remembered between launches, all of it a convenience: the workspace
/// last used, and per Jira project the Clockify project and tags last logged
/// against, so "SWEB" comes back already pointing at "SIGRA WEB · Tarefa".
enum ClockifyPreferences {
    private static let workspaceKey = "clockifyWorkspace"
    private static let projectsKey = "clockifyProjectByJiraProject"
    private static let tagsKey = "clockifyTagsByJiraProject"

    static var workspaceID: String? {
        get { UserDefaults.standard.string(forKey: workspaceKey) }
        set { UserDefaults.standard.set(newValue, forKey: workspaceKey) }
    }

    static func projectID(forJiraProject key: String, workspaceID: String) -> String? {
        dictionary(projectsKey)["\(workspaceID)/\(key)"] as? String
    }

    static func tagIDs(forJiraProject key: String, workspaceID: String) -> [String] {
        dictionary(tagsKey)["\(workspaceID)/\(key)"] as? [String] ?? []
    }

    static func remember(projectID: String?, tagIDs: [String], forJiraProject key: String, workspaceID: String) {
        var projects = dictionary(projectsKey)
        projects["\(workspaceID)/\(key)"] = projectID
        UserDefaults.standard.set(projects, forKey: projectsKey)

        var tags = dictionary(tagsKey)
        tags["\(workspaceID)/\(key)"] = tagIDs
        UserDefaults.standard.set(tags, forKey: tagsKey)
    }

    private static func dictionary(_ key: String) -> [String: Any] {
        UserDefaults.standard.dictionary(forKey: key) ?? [:]
    }
}

enum ClockifyCredentialsStore {
    private static let service = "luckxy.tech.GitHalls.clockify"
    private static let account = "api-key"

    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static var isConfigured: Bool { apiKey != nil }

    static func save(apiKey: String) throws {
        forget()

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(apiKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw JiraCredentialsError.keychain(status) }
    }

    static func forget() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
