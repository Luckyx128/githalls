//
//  JiraViewModel+Files.swift
//  GitHalls
//

import Foundation

/// Worklogs and attachments.
extension JiraViewModel {
    // MARK: - Worklogs

    func loadWorklogs(for key: String) async throws {
        worklogsByIssue[key] = try await client().worklogs(key: key)
    }

    @discardableResult
    func logWork(on key: String, seconds: Int, started: Date? = nil, comment: String? = nil) async -> Bool {
        let pending = JiraWorklog(id: JiraComment.pendingPrefix + UUID().uuidString, timeSpentSeconds: seconds,
                                  started: started ?? Date(), comment: comment ?? "")
        worklogsByIssue[key, default: []].append(pending)

        do {
            let saved = try await client().addWorklog(key: key, seconds: seconds, started: started, comment: comment)
            if let index = worklogsByIssue[key]?.firstIndex(where: { $0.id == pending.id }) {
                worklogsByIssue[key]?[index] = saved
            }
            report(key, "Logged \(saved.timeSpent) on \(key).", failed: false)
            return true
        } catch {
            worklogsByIssue[key]?.removeAll { $0.id == pending.id }
            report(key, error.localizedDescription, failed: true)
            return false
        }
    }

    @discardableResult
    func deleteWorklog(on key: String, id: String) async -> Bool {
        guard let index = worklogsByIssue[key]?.firstIndex(where: { $0.id == id }),
              let original = worklogsByIssue[key]?[index]
        else { return false }

        worklogsByIssue[key]?.remove(at: index)

        do {
            try await client().deleteWorklog(key: key, id: id)
            report(key, "Worklog removed from \(key).", failed: false)
            return true
        } catch {
            let at = min(index, worklogsByIssue[key]?.count ?? 0)
            worklogsByIssue[key, default: []].insert(original, at: at)
            report(key, error.localizedDescription, failed: true)
            return false
        }
    }

    // MARK: - Attachments

    func loadAttachments(for key: String) async throws {
        attachmentsByIssue[key] = try await client().attachments(key: key)
    }

    @discardableResult
    func attach(to key: String, filename: String, data: Data, mimeType: String) async -> Bool {
        do {
            let saved = try await client().uploadAttachment(key: key, filename: filename, data: data, mimeType: mimeType)
            attachmentsByIssue[key, default: []].append(contentsOf: saved)
            report(key, "\(filename) attached to \(key).", failed: false)
            return true
        } catch {
            report(key, error.localizedDescription, failed: true)
            return false
        }
    }

    func download(_ attachment: JiraAttachment) async throws -> Data {
        try await client().downloadAttachment(attachment)
    }

    @discardableResult
    func deleteAttachment(on key: String, id: String) async -> Bool {
        guard let index = attachmentsByIssue[key]?.firstIndex(where: { $0.id == id }),
              let original = attachmentsByIssue[key]?[index]
        else { return false }

        attachmentsByIssue[key]?.remove(at: index)

        do {
            try await client().deleteAttachment(id: id)
            report(key, "\(original.filename) deleted from \(key).", failed: false)
            return true
        } catch {
            let at = min(index, attachmentsByIssue[key]?.count ?? 0)
            attachmentsByIssue[key, default: []].insert(original, at: at)
            report(key, error.localizedDescription, failed: true)
            return false
        }
    }
}
