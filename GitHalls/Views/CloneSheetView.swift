//
//  CloneSheetView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 31/08/26.
//

import SwiftUI
import AppKit

struct CloneSheetView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var destinationFolder = ClonePreferences.defaultFolder

    private var suggestedName: String {
        GitService.repositoryName(fromCloneURL: urlString)
    }

    private var destinationURL: URL {
        destinationFolder.appending(path: suggestedName.isEmpty ? "repository" : suggestedName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clone Repository")
                .font(.title2)
                .bold()

            TextField("Repository URL", text: $urlString, prompt: Text("https://github.com/user/repo.git"))
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Into:")
                Text(destinationURL.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.prompt = "Choose"
                    if panel.runModal() == .OK, let url = panel.url {
                        destinationFolder = url
                        ClonePreferences.defaultFolder = url
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(viewModel.isCloning ? "Cloning…" : "Clone") {
                    let destination = destinationURL
                    Task {
                        await viewModel.clone(url: urlString, into: destination)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isCloning)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
