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
                            branchRow(name: name, isCurrent: viewModel.currentBranch == name, creator: viewModel.branchCreatorLabels["local:" + name])
                        }
                    } 
                }

                Section("Local") {
                    ForEach(localBranches) { branch in
                        branchRow(name: branch.name, isCurrent: branch.isCurrent, creator: viewModel.branchCreatorLabels[branch.id])
                    }
                }

                if !remoteBranches.isEmpty {
                    Section("Remote") {
                       ForEach(remoteBranches) { branch in
                           branchRow(name: branch.name, isCurrent: false, switchTo: Branch.remoteShortName(from: branch.name), creator: viewModel.branchCreatorLabels[branch.id])
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
        .frame(width: 300)
        .task {
            await viewModel.loadBranches()
            await viewModel.loadBranchCreators()
        }
    }

    @ViewBuilder
    private func branchRow(name: String, isCurrent: Bool, switchTo: String? = nil, creator: String? = nil) -> some View {
        Button {
            Task { await viewModel.switchBranch(to: switchTo ?? name) }
        } label: {
            HStack {
                Text(name)
                Spacer()
                if let creator {
                    Text(creator)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(BranchCreator.tooltip(for: creator))
                }
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
