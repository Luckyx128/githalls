//
//  JiraClient+Files.swift
//  GitHalls
//

import Foundation

/// Worklogs and attachments.
extension JiraClient {
    // MARK: - Worklogs

    func worklogs(key: String) async throws -> [JiraWorklog] {
        try await objects(path: Self.path(for: key, suffix: "/worklog"), key: "worklogs")
            .compactMap(JiraWorklog.init(json:))
    }

    func addWorklog(key: String, seconds: Int, started: Date? = nil, comment: String? = nil) async throws -> JiraWorklog {
        var body: [String: Any] = ["timeSpentSeconds": seconds]
        if let started { body["started"] = Self.timestamp.string(from: started) }
        if let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["comment"] = JiraADF.document(from: comment)
        }

        var request = request(path: Self.path(for: key, suffix: "/worklog"), method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        guard let object = try await send(request) as? [String: Any], let worklog = JiraWorklog(json: object)
        else { throw JiraError.malformedResponse }
        return worklog
    }

    func deleteWorklog(key: String, id: String) async throws {
        _ = try await send(request(path: Self.path(for: key, suffix: "/worklog/" + Self.escape(id)), method: "DELETE"))
    }

    // MARK: - Attachments

    func attachments(key: String) async throws -> [JiraAttachment] {
        let path = Self.path(for: key, suffix: "") + "?fields=attachment"
        guard let object = try await send(request(path: path)) as? [String: Any],
              let fields = object["fields"] as? [String: Any]
        else { throw JiraError.malformedResponse }

        return (fields["attachment"] as? [[String: Any]] ?? []).compactMap(JiraAttachment.init(json:))
    }

    /// Uploads one file as multipart form data; answers what Jira stored.
    func uploadAttachment(key: String, filename: String, data: Data, mimeType: String) async throws -> [JiraAttachment] {
        let boundary = "GitHalls-" + UUID().uuidString
        let safeName = filename.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = request(path: Self.path(for: key, suffix: "/attachments"), method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Without this Jira refuses the upload as a possible cross-site request.
        request.setValue("no-check", forHTTPHeaderField: "X-Atlassian-Token")
        request.timeoutInterval = 120
        request.httpBody = body

        guard let raw = try await send(request) as? [[String: Any]] else { throw JiraError.malformedResponse }
        return raw.compactMap(JiraAttachment.init(json:))
    }

    /// The file's bytes. Credentials only go to the site itself: an attachment
    /// URL that points elsewhere is refused rather than sent a token.
    func downloadAttachment(_ attachment: JiraAttachment) async throws -> Data {
        guard attachment.contentURL.host?.lowercased() == credentials.site.host?.lowercased() else {
            throw JiraError.malformedResponse
        }

        var request = URLRequest(url: attachment.contentURL)
        request.setValue(credentials.authorization, forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        return try await sendData(request)
    }

    func deleteAttachment(id: String) async throws {
        _ = try await send(request(path: "/rest/api/3/attachment/" + Self.escape(id), method: "DELETE"))
    }
}
