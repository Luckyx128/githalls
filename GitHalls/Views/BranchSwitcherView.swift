//
//  BranchSwitcherView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 30/08/26.
//

import Foundation
import SwiftUI

struct BranchSwitcherView: View {
    @Bindable var viewModel: RepositoryViewModel
    @State private var newBranchName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(viewModel.branches) { branch in
                Button {
                    Task { await viewModel.switchBranch(to: branch.name) }
                } label: {
                    HStack {
                        Text(branch.name)
                        Spacer()
                        if branch.isCurrent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 150, maxHeight: 250)

            Divider()

            HStack {
                TextField("New branch name", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)
                Button("Create") {
                    let name = newBranchName
                    newBranchName = ""
                    Task { await viewModel.createBranch(named: name) }
                }
                .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .frame(width: 260)
        .task {
            await viewModel.loadBranches()
        }
    }
}
