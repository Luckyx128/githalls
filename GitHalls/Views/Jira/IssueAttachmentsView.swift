//
//  IssueAttachmentsView.swift
//  GitHalls
//

import SwiftUI
import UniformTypeIdentifiers

/// Files on an issue: list, add (picker or drop), save, delete.
struct IssueAttachmentsView: View {
    let issueKey: String
    @Bindable var jiraViewModel: JiraViewModel

    @State private var isImporting = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var deleting: JiraAttachment?

    private var attachments: [JiraAttachment] { jiraViewModel.attachmentsByIssue[issueKey] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Attachments").font(.headline)
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Add File…") { isImporting = true }
            }

            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }

            ForEach(attachments) { attachment in
                HStack(spacing: 8) {
                    Image(systemName: attachment.isImage ? "photo" : "doc")
                    Text(attachment.filename).lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await save(attachment) } } label: { Image(systemName: "arrow.down.circle") }
                        .help("Save a copy")
                    Button { deleting = attachment } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete attachment")
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .font(.callout)
            }

            if attachments.isEmpty {
                Text("No attachments. Drop a file here.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .dropDestination(for: URL.self) { urls, _ in
            Task { await upload(urls) }
            return true
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await upload(urls) } }
        }
        .confirmationDialog("Delete this attachment?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { attachment in
            Button("Delete \(attachment.filename)", role: .destructive) {
                Task { await jiraViewModel.deleteAttachment(on: issueKey, id: attachment.id) }
            }
        }
        .task(id: issueKey) {
            do { try await jiraViewModel.loadAttachments(for: issueKey) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func upload(_ urls: [URL]) async {
        isWorking = true
        defer { isWorking = false }

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "Could not read \(url.lastPathComponent)."
                continue
            }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            if await jiraViewModel.attach(to: issueKey, filename: url.lastPathComponent, data: data, mimeType: type) {
                errorMessage = nil
            } else {
                errorMessage = jiraViewModel.actionMessage
            }
        }
    }

    private func save(_ attachment: JiraAttachment) async {
        do {
            let data = try await jiraViewModel.download(attachment)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = attachment.filename
            if panel.runModal() == .OK, let url = panel.url { try data.write(to: url) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
