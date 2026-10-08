//
//  JiraAttachment.swift
//  GitHalls
//

import Foundation

struct JiraAttachment: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let filename: String
    var size: Int
    var mimeType: String
    let contentURL: URL
    var thumbnailURL: URL?
    var author: JiraUser?
    var created: Date?

    var isImage: Bool { mimeType.hasPrefix("image/") }

    init(id: String, filename: String, size: Int = 0, mimeType: String = "application/octet-stream",
         contentURL: URL, thumbnailURL: URL? = nil, author: JiraUser? = nil, created: Date? = nil) {
        self.id = id
        self.filename = filename
        self.size = size
        self.mimeType = mimeType
        self.contentURL = contentURL
        self.thumbnailURL = thumbnailURL
        self.author = author
        self.created = created
    }

    init?(json raw: [String: Any]) {
        guard let id = raw["id"] as? String,
              let filename = raw["filename"] as? String,
              let content = (raw["content"] as? String).flatMap(URL.init(string:))
        else { return nil }

        self.init(
            id: id,
            filename: filename,
            size: raw["size"] as? Int ?? 0,
            mimeType: raw["mimeType"] as? String ?? "application/octet-stream",
            contentURL: content,
            thumbnailURL: (raw["thumbnail"] as? String).flatMap(URL.init(string:)),
            author: JiraUser(json: raw["author"] as? [String: Any]),
            created: (raw["created"] as? String).flatMap(JiraClient.timestamp.date(from:))
        )
    }
}
