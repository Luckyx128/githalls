//
//  FilePreview.swift
//  GitHalls
//

import Foundation

/// Where one side of a binary change is read from.
enum FileRevisionSource: Equatable, Hashable {
    /// The file on disk. The only side no revision names.
    case workingTree
    case revision(String)
}

/// What a file with no text diff can be shown as.
///
/// git only tells us a file is binary, never what kind — so the decision comes
/// from the path, which is the one thing available before any bytes are read.
enum FilePreview {
    enum Kind {
        /// Something the app can draw. Shown before and after, side by side.
        case image

        /// Anything else: a size, a type, and a way to open it where it belongs.
        case other
    }

    /// Formats `Image` can decode on macOS. SVG is absent on purpose: git diffs
    /// it as text, so it never reaches here.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "webp", "heic", "heif", "tif", "tiff", "ico"
    ]

    static func kind(for path: String) -> Kind {
        let ext = (path as NSString).pathExtension.lowercased()

        return imageExtensions.contains(ext) ? .image : .other
    }

    /// "1.2 MB" — what a binary change has instead of a line count.
    static func formattedSize(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
