//
//  ClockifyClient.swift
//  GitHalls
//

import Foundation

/// The Clockify calls this app makes: who am I, where can I log, and the three
/// writes — log time, start a timer, stop it. Clockify knows nothing about
/// Jira here: an entry names the issue only in its description and, when the
/// workspace has one, a task called after the key.
struct ClockifyClient {
    let apiKey: String

    /// Tests hand in a session wired to a mock `URLProtocol`.
    var session: URLSession = .shared

    var baseURL = URL(string: "https://api.clockify.me/api/v1")!

    /// Clockify's default page is 50; workspaces with years of projects need more.
    static let listPageSize = 500

    func user() async throws -> ClockifyUser {
        guard let object = try await send(request(path: "/user")) as? [String: Any],
              let id = object["id"] as? String
        else { throw ClockifyError.malformedResponse }
        return ClockifyUser(
            id: id,
            name: object["name"] as? String ?? object["email"] as? String ?? id,
            activeWorkspaceID: object["activeWorkspace"] as? String ?? object["defaultWorkspace"] as? String
        )
    }

    func workspaces() async throws -> [ClockifyWorkspace] {
        try await list(path: "/workspaces").compactMap { raw in
            guard let id = raw["id"] as? String else { return nil }
            return ClockifyWorkspace(id: id, name: raw["name"] as? String ?? id)
        }
    }

    func projects(workspaceID: String) async throws -> [ClockifyProject] {
        let path = "/workspaces/\(workspaceID)/projects"
        let query = ["archived": "false", "page-size": "\(Self.listPageSize)", "sort-column": "NAME"]
        return try await list(path: path, query: query).compactMap { raw in
            guard let id = raw["id"] as? String else { return nil }
            let client = (raw["clientName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return ClockifyProject(id: id, name: raw["name"] as? String ?? id, clientName: client)
        }
    }

    /// Active tasks whose name contains `name`; an issue key finds the task the
    /// Jira integration created for it.
    func tasks(workspaceID: String, projectID: String, name: String? = nil) async throws -> [ClockifyTask] {
        let path = "/workspaces/\(workspaceID)/projects/\(projectID)/tasks"
        var query = ["is-active": "true", "page-size": "50"]
        if let name, !name.isEmpty { query["name"] = name }
        return try await list(path: path, query: query).compactMap { raw in
            guard let id = raw["id"] as? String else { return nil }
            return ClockifyTask(id: id, name: raw["name"] as? String ?? id)
        }
    }

    func tags(workspaceID: String) async throws -> [ClockifyTag] {
        let query = ["archived": "false", "page-size": "\(Self.listPageSize)"]
        return try await list(path: "/workspaces/\(workspaceID)/tags", query: query).compactMap { raw in
            guard let id = raw["id"] as? String else { return nil }
            return ClockifyTag(id: id, name: raw["name"] as? String ?? id)
        }
    }

    /// The timer running for this user, wherever it was started; nil when none is.
    func runningEntry(workspaceID: String, userID: String) async throws -> ClockifyTimeEntry? {
        let path = "/workspaces/\(workspaceID)/user/\(userID)/time-entries"
        return try await list(path: path, query: ["in-progress": "true"]).compactMap(Self.entry(from:)).first
    }

    /// Logs time when `entry.end` is set; starts a timer when it is not.
    func addEntry(workspaceID: String, _ entry: ClockifyNewEntry) async throws -> ClockifyTimeEntry {
        var request = request(path: "/workspaces/\(workspaceID)/time-entries", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(for: entry))

        guard let object = try await send(request) as? [String: Any],
              let created = Self.entry(from: object)
        else { throw ClockifyError.malformedResponse }
        return created
    }

    /// Stops the user's running timer at `end`.
    func stopTimer(workspaceID: String, userID: String, end: Date = .now) async throws -> ClockifyTimeEntry {
        var request = request(path: "/workspaces/\(workspaceID)/user/\(userID)/time-entries", method: "PATCH")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["end": Self.timestamp(end)])

        guard let object = try await send(request) as? [String: Any],
              let stopped = Self.entry(from: object)
        else { throw ClockifyError.malformedResponse }
        return stopped
    }

    // MARK: - Payloads

    nonisolated static func body(for entry: ClockifyNewEntry) -> [String: Any] {
        var body: [String: Any] = [
            "start": timestamp(entry.start),
            "description": entry.description
        ]
        if let end = entry.end { body["end"] = timestamp(end) }
        if let projectID = entry.projectID { body["projectId"] = projectID }
        if let taskID = entry.taskID { body["taskId"] = taskID }
        if !entry.tagIDs.isEmpty { body["tagIds"] = entry.tagIDs }
        return body
    }

    nonisolated static func entry(from raw: [String: Any]) -> ClockifyTimeEntry? {
        guard let id = raw["id"] as? String,
              let interval = raw["timeInterval"] as? [String: Any],
              let start = (interval["start"] as? String).flatMap(date(from:))
        else { return nil }

        return ClockifyTimeEntry(
            id: id,
            description: raw["description"] as? String ?? "",
            projectID: raw["projectId"] as? String,
            taskID: raw["taskId"] as? String,
            tagIDs: raw["tagIds"] as? [String] ?? [],
            start: start,
            end: (interval["end"] as? String).flatMap(date(from:))
        )
    }

    /// Clockify writes UTC with or without milliseconds; it reads it without.
    nonisolated static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    nonisolated static func date(from text: String) -> Date? {
        (try? Date(text, strategy: .iso8601))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    // MARK: - Transport

    private func list(path: String, query: [String: String] = [:]) async throws -> [[String: Any]] {
        guard let array = try await send(request(path: path, query: query)) as? [[String: Any]] else {
            throw ClockifyError.malformedResponse
        }
        return array
    }

    func request(path: String, method: String = "GET", query: [String: String] = [:]) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components?.url ?? baseURL)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        return request
    }

    /// The decoded JSON body; an empty body reads as an empty object.
    func send(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClockifyError.malformedResponse }

        switch http.statusCode {
        case 200..<300:
            guard !data.isEmpty else { return [String: Any]() }
            return try JSONSerialization.jsonObject(with: data)
        case 401, 403:
            throw ClockifyError.unauthorized
        default:
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ClockifyError.http(status: http.statusCode, message: object?["message"] as? String)
        }
    }
}
