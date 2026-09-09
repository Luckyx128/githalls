//
//  RenameBranchSheetView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import SwiftUI

struct RenameBranchSheetView: View {
    @Bindable var viewModel: RepositoryViewModel
    let branch: String
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    private var isUnchanged: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == branch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename \"\(branch)\"")
                .font(.title2)
                .bold()

            TextField("New name", text: $name)
                .textFieldStyle(.roundedBorder)

            Text("Renames the local branch only. If it has already been pushed, the old name stays on the remote until you delete it there.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") {
                    let newName = name
                    Task {
                        await viewModel.renameBranch(branch, to: newName)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isUnchanged || viewModel.isMutatingBranch)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { name = branch }
    }
}
