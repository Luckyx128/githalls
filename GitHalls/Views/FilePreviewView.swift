//
//  FilePreviewView.swift
//  GitHalls
//

import AppKit
import SwiftUI

/// What stands in for the diff of a file git has no text for.
///
/// An image is shown as an image, before beside after, because "Binary file not
/// shown" is the one thing about a picture nobody needs to be told. Anything
/// else states what it is and how big it got, which is the whole of what a diff
/// could honestly say about it.
///
/// Loads its own bytes: a commit can carry twenty binaries and only the one on
/// screen is worth a process.
struct FilePreviewView: View {
    let viewModel: RepositoryViewModel
    let path: String
    let before: FileRevisionSource
    let after: FileRevisionSource

    @State private var beforeData: Data?
    @State private var afterData: Data?
    @State private var isLoading = true

    @Environment(\.openURL) private var openURL

    private var kind: FilePreview.Kind { FilePreview.kind(for: path) }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else if beforeData == nil && afterData == nil {
                // Both sides missing means git could not hand over either one.
                Label("This file's contents could not be read.", systemImage: "questionmark.square.dashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            } else if kind == .image {
                imageComparison
            } else {
                otherFileCard
            }
        }
        .task(id: Load(path: path, before: before, after: after)) {
            await load()
        }
    }

    /// What a reload is for: the same view is reused as the selection moves.
    private struct Load: Equatable {
        let path: String
        let before: FileRevisionSource
        let after: FileRevisionSource
    }

    private func load() async {
        isLoading = true
        beforeData = await viewModel.fileBytes(path: path, revision: before.revisionArgument)
        afterData = await viewModel.fileBytes(path: path, revision: after.revisionArgument)
        isLoading = false
    }

    // MARK: - Images

    private var imageComparison: some View {
        HStack(alignment: .top, spacing: 16) {
            if let beforeData {
                imageSide(beforeData, title: afterData == nil ? "Deleted" : "Before")
            }

            if let afterData {
                imageSide(afterData, title: beforeData == nil ? "Added" : "After")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private func imageSide(_ data: Data, title: String) -> some View {
        VStack(spacing: 6) {
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 420, maxHeight: 420)
                    // The checkerboard is what makes a transparent PNG readable.
                    .background(CheckerboardBackground())
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.25)))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(dimensions(of: image))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                // The extension said image and the decoder disagreed. Say so
                // rather than showing an empty frame.
                Label("Not a format this Mac can draw", systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(24)
            }

            Text("\(title) · \(FilePreview.formattedSize(data.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dimensions(of image: NSImage) -> String {
        guard let rep = image.representations.first else { return "" }

        return "\(rep.pixelsWide) × \(rep.pixelsHigh) px"
    }

    // MARK: - Everything else

    private var otherFileCard: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFileType: (path as NSString).pathExtension))
                .resizable()
                .frame(width: 48, height: 48)

            Text(typeLabel)
                .font(.headline)

            Text(sizeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Only the working tree has a file to open; a past revision is not
            // on disk anywhere.
            if after == .workingTree, let url = viewModel.repositoryURL?.appending(path: path) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .controlSize(.small)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var typeLabel: String {
        let ext = (path as NSString).pathExtension.uppercased()

        return ext.isEmpty ? "Binary file" : "\(ext) file"
    }

    private var sizeLabel: String {
        switch (beforeData?.count, afterData?.count) {
        case let (before?, after?):
            before == after
                ? FilePreview.formattedSize(after)
                : "\(FilePreview.formattedSize(before)) → \(FilePreview.formattedSize(after))"
        case let (nil, after?):
            "Added · \(FilePreview.formattedSize(after))"
        case let (before?, nil):
            "Deleted · \(FilePreview.formattedSize(before))"
        default:
            ""
        }
    }
}

/// The grey grid image editors use behind transparency, so an alpha channel
/// reads as transparent instead of as white.
private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let square = 8.0
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))

            for row in 0..<Int(size.height / square + 1) {
                for column in 0..<Int(size.width / square + 1) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: Double(column) * square, y: Double(row) * square,
                                      width: square, height: square)
                    context.fill(Path(rect), with: .color(.gray.opacity(0.25)))
                }
            }
        }
    }
}

private extension FileRevisionSource {
    /// What `RepositoryViewModel.fileBytes` wants: nil for the working tree.
    var revisionArgument: String? {
        switch self {
        case .workingTree: nil
        case .revision(let revision): revision
        }
    }
}
