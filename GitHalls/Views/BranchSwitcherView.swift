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

    private var localBranches: [Branch] {
        viewModel.branches.filter { !$0.isRemote }
    }

    private var remoteBranches: [Branch] {
        viewModel.branches.filter { $0.isRemote }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                if !viewModel.recentBranchNames.isEmpty {
                    Section("Recent") {
                        ForEach(viewModel.recentBranchNames, id: \.self) { name in
                            branchRow(name: name, isCurrent: viewModel.currentBranch == name)
                        }
                    } 
                }

                Section("Local") {
                    ForEach(localBranches) { branch in
                        branchRow(name: branch.name, isCurrent: branch.isCurrent)
                    }
                }

                if !remoteBranches.isEmpty {
                    Section("Remote") {
                       ForEach(remoteBranches) { branch in
                           branchRow(name: branch.name, isCurrent: false, switchTo: shortName(for: branch.name))
                       }
                   }
                }
            }
            .frame(minHeight: 220, maxHeight: 340)

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
        .frame(width: 280)
        .task {
            await viewModel.loadBranches()
        }
    }

    @ViewBuilder
    private func branchRow(name: String, isCurrent: Bool, switchTo: String? = nil) -> some View {
        Button {
            Task { await viewModel.switchBranch(to: switchTo ?? name) }
        } label: {
            HStack {
                Text(name)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func shortName(for remoteBranchName: String) -> String {
        guard let slashIndex = remoteBranchName.firstIndex(of: "/") else { return remoteBranchName }
        return String(remoteBranchName[remoteBranchName.index(after: slashIndex)...])
    }
}
