//
//  JiraCredentials.swift
//  GitHalls
//

import Foundation
import Security

struct JiraCredentials: Equatable {
    let site: URL
    let email: String
    let token: String

    var authorization: String {
        let pair = Data("\(email):\(token)".utf8).base64EncodedString()
        return "Basic \(pair)"
    }
}

enum JiraPreferences {
    private static let siteKey = "jiraSite"
    private static let emailKey = "jiraEmail"

    static var site: URL? {
        get { UserDefaults.standard.string(forKey: siteKey).flatMap(URL.init(string:)) }
        set { UserDefaults.standard.set(newValue?.absoluteString, forKey: siteKey) }
    }

    static var email: String {
        get { UserDefaults.standard.string(forKey: emailKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: emailKey) }
    }
}

enum JiraCredentialsError: LocalizedError {
    case keychain(OSStatus)
    case missing

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Keychain refused the request (code \(status))."
        case .missing:
            "Jira is not connected yet."
        }
    }
}

enum JiraCredentialsStore {
    private static let service = "luckxy.tech.GitHalls.jira"

    static var current: JiraCredentials? {
        guard let site = JiraPreferences.site, !JiraPreferences.email.isEmpty,
              let token = readToken(account: JiraPreferences.email)
        else { return nil }
        return JiraCredentials(site: site, email: JiraPreferences.email, token: token)
    }

    static var isConfigured: Bool { current != nil }

    static func save(site: URL, email: String, token: String) throws {
        try store(token: token, account: email)
        JiraPreferences.site = site
        JiraPreferences.email = email
    }

    static func forget() {
        deleteToken(account: JiraPreferences.email)
        JiraPreferences.site = nil
        JiraPreferences.email = ""
    }

    // MARK: - Keychain

    private static func store(token: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw JiraCredentialsError.keychain(status) }
    }

    private static func readToken(account: String) -> String? {
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

    private static func deleteToken(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
