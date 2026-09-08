//
//  JiraClient.swift
//  GitHalls
//

import Foundation

/// The three Jira Cloud calls this app makes: who am I, which issues match a
/// JQL query, and everything about one issue. Nothing here caches or retries —
/// the view model decides when to ask, and a rate limit comes back as an error
/// the user can read.
struct JiraClient {
    let credentials: JiraCredentials

    private static let searchPath = "/rest/api/3/search/jql"
    private static let issuePath = "/rest/api/3/issue/"

    /// Only what a card renders; asking for everything costs Jira time it
    /// doesn't need to spend.
    private static let cardFields = ["summary", "status", "issuetype", "priority", "updated", "assignee"]

    /// What the issue window shows on top of the card.
    private static let detailFields = [
        "summary", "status", "issuetype", "priority", "updated", "created",
        "assignee", "reporter", "labels", "description"
    ]

    func myself() async throws -> (accountID: String, displayName: String) {
        let json = try await send(request(path: "/rest/api/3/myself"))
        guard let object = json as? [String: Any],
              let accountID = object["accountId"] as? String
        else { throw JiraError.malformedResponse }
        return (accountID, object["displayName"] as? String ?? credentials.email)
    }

    func search(jql: String, limit: Int = 50) async throws -> [JiraIssue] {
        var request = request(path: Self.searchPath, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jql": jql,
            "fields": Self.cardFields,
            "maxResults": limit
        ])

        let json = try await send(request)
        guard let object = json as? [String: Any],
              let issues = object["issues"] as? [[String: Any]]
        else { throw JiraError.malformedResponse }

        return issues.compactMap(Self.issue(from:))
    }

    /// One issue with its description and people, for the detail window.
    func issue(key: String) async throws -> JiraIssue {
        let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let path = Self.issuePath + escaped + "?fields=" + Self.detailFields.joined(separator: ",")

        let json = try await send(request(path: path))
        guard let object = json as? [String: Any], let issue = Self.issue(from: object) else {
            throw JiraError.malformedResponse
        }
        return issue
    }

    func browseURL(for key: String) -> URL {
        credentials.site.appendingPathComponent("browse").appendingPathComponent(key)
    }

    // MARK: - Transporte

    private func request(path: String, method: String = "GET") -> URLRequest {
        
        let url = URL(string: credentials.site.absoluteString + path) ?? credentials.site
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        return request
    }

    private func send(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JiraError.malformedResponse }

        switch http.statusCode {
        case 200..<300:
            guard !data.isEmpty else { return [String: Any]() }
            return try JSONSerialization.jsonObject(with: data)
        case 401, 403:
            throw JiraError.unauthorized
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw JiraError.rateLimited(retryAfter: retry ?? 60)
        default:
            throw JiraError.http(status: http.statusCode, message: Self.message(from: data))
        }
    }

    private static func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let messages = object["errorMessages"] as? [String], let first = messages.first {
            return first
        }
        if let errors = object["errors"] as? [String: String], let first = errors.values.first {
            return first
        }
        return nil
    }

    // MARK: - Decodificação

    static func issue(from raw: [String: Any]) -> JiraIssue? {
        guard let key = raw["key"] as? String,
              let fields = raw["fields"] as? [String: Any]
        else { return nil }

        let status = fields["status"] as? [String: Any]
        let category = status?["statusCategory"] as? [String: Any]

        return JiraIssue(
            key: key,
            summary: fields["summary"] as? String ?? key,
            status: status?["name"] as? String ?? "—",
            statusCategory: category?["key"] as? String ?? "indeterminate",
            type: (fields["issuetype"] as? [String: Any])?["name"] as? String ?? "Task",
            priority: (fields["priority"] as? [String: Any])?["name"] as? String,
            updated: (fields["updated"] as? String).flatMap(timestamp.date(from:)) ?? .distantPast,
            assigneeName: (fields["assignee"] as? [String: Any])?["displayName"] as? String,
            reporterName: (fields["reporter"] as? [String: Any])?["displayName"] as? String,
            created: (fields["created"] as? String).flatMap(timestamp.date(from:)),
            labels: fields["labels"] as? [String] ?? [],
            // A missing key means the search never asked; a present one that is
            // null means Jira has no description. The window tells them apart.
            description: fields.keys.contains("description")
                ? JiraADF.plainText(from: fields["description"])
                : nil
        )
    }

    /// O Jira manda `2026-08-07T14:02:11.123-0300`: fuso sem dois-pontos, que o
    /// `ISO8601DateFormatter` não aceita.
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()
}
