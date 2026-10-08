//
//  JiraClient+Comments.swift
//  GitHalls
//

import Foundation

/// Comments are written as plain text and sent as ADF; they come back flattened
/// the same way, so what a person typed is what they read.
extension JiraClient {
    /// Oldest first, every page.
    func comments(key: String) async throws -> [JiraComment] {
        try await objects(path: Self.path(for: key, suffix: "/comment"), key: "comments", query: ["orderBy": "created"])
            .compactMap(JiraComment.init(json:))
    }

    func addComment(key: String, text: String) async throws -> JiraComment {
        try await writeComment(path: Self.path(for: key, suffix: "/comment"), method: "POST", text: text)
    }

    func editComment(key: String, id: String, text: String) async throws -> JiraComment {
        try await writeComment(path: Self.path(for: key, suffix: "/comment/" + Self.escape(id)), method: "PUT", text: text)
    }

    func deleteComment(key: String, id: String) async throws {
        _ = try await send(request(path: Self.path(for: key, suffix: "/comment/" + Self.escape(id)), method: "DELETE"))
    }

    private func writeComment(path: String, method: String, text: String) async throws -> JiraComment {
        var request = request(path: path, method: method)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["body": JiraADF.document(from: text)])

        guard let object = try await send(request) as? [String: Any], let comment = JiraComment(json: object)
        else { throw JiraError.malformedResponse }
        return comment
    }
}
