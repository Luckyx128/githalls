//
//  JiraUser.swift
//  GitHalls
//

import Foundation

struct JiraUser: Identifiable, Equatable, Hashable, Sendable {
    let accountID: String
    let displayName: String
    var email: String?
    var avatarURL: URL?
    var active = true
    var accountType: String?

    var id: String { accountID }

    init(accountID: String, displayName: String, email: String? = nil, avatarURL: URL? = nil, active: Bool = true, accountType: String? = nil) {
        self.accountID = accountID
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
        self.active = active
        self.accountType = accountType
    }

    init?(json raw: [String: Any]?) {
        guard let raw, let accountID = raw["accountId"] as? String else { return nil }

        self.init(
            accountID: accountID,
            displayName: raw["displayName"] as? String ?? accountID,
            email: raw["emailAddress"] as? String,
            avatarURL: ((raw["avatarUrls"] as? [String: Any])?["48x48"] as? String).flatMap(URL.init(string:)),
            active: raw["active"] as? Bool ?? true,
            accountType: raw["accountType"] as? String
        )
    }
}
