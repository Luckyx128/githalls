//
//  JiraViewModel+Comments.swift
//  GitHalls
//

import Foundation

/// Comments per issue, kept here so every window on the same issue agrees.
/// Writes show up at once and are taken back when Jira refuses them.
extension JiraViewModel {
    /// Fetches and stores the issue's comments.
    @discardableResult
    func loadComments(for key: String) async throws -> [JiraComment] {
        let comments = try await client().comments(key: key)
        commentsByIssue[key] = comments
        return comments
    }

    @discardableResult
    func addComment(to key: String, text: String) async -> Bool {
        let pending = JiraComment(id: JiraComment.pendingPrefix + UUID().uuidString, body: text, created: Date())
        commentsByIssue[key, default: []].append(pending)

        do {
            let saved = try await client().addComment(key: key, text: text)
            replaceComment(pending.id, in: key) { $0 = saved }
            report(key, "Comment added to \(key).", failed: false)
            return true
        } catch {
            commentsByIssue[key]?.removeAll { $0.id == pending.id }
            report(key, error.localizedDescription, failed: true)
            return false
        }
    }

    @discardableResult
    func editComment(on key: String, id: String, text: String) async -> Bool {
        guard let original = commentsByIssue[key]?.first(where: { $0.id == id }) else { return false }

        replaceComment(id, in: key) { $0.body = text }

        do {
            let saved = try await client().editComment(key: key, id: id, text: text)
            replaceComment(id, in: key) { $0 = saved }
            report(key, "Comment on \(key) updated.", failed: false)
            return true
        } catch {
            replaceComment(id, in: key) { $0 = original }
            report(key, error.localizedDescription, failed: true)
            return false
        }
    }

    @discardableResult
    func deleteComment(on key: String, id: String) async -> Bool {
        guard let index = commentsByIssue[key]?.firstIndex(where: { $0.id == id }),
              let original = commentsByIssue[key]?[index]
        else { return false }

        commentsByIssue[key]?.remove(at: index)

        do {
            try await client().deleteComment(key: key, id: id)
            report(key, "Comment on \(key) deleted.", failed: false)
            return true
        } catch {
            // Back where it was, unless the list changed under us.
            let at = min(index, commentsByIssue[key]?.count ?? 0)
            commentsByIssue[key, default: []].insert(original, at: at)
            report(key, error.localizedDescription, failed: true)
            return false
        }
    }

    private func replaceComment(_ id: String, in key: String, with change: (inout JiraComment) -> Void) {
        guard let index = commentsByIssue[key]?.firstIndex(where: { $0.id == id }) else { return }
        change(&commentsByIssue[key]![index])
    }
}
