//
//  CreateBranchFromCommitSheetView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import Foundation
import SwiftUI

struct CreateBranchFromCommitSheetView: View {
    @Bindable var viewModel: RepositoryViewModel
    let commit: GraphCommit
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var switchTo = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Branch")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 6) {
                TextField("Branch name", text: $name)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 6) {
                    Text("Starting at")
                    Text(commit.shortHash)
                        .font(.system(.caption, design: .monospaced))
                    Text(commit.summary)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Toggle("Switch to the new branch", isOn: $switchTo)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") {
                    let branchName = name
                    let shouldSwitch = switchTo
                    Task {
                        await viewModel.createBranch(named: branchName, from: commit.hash, switchTo: shouldSwitch)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isMutatingBranch)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
