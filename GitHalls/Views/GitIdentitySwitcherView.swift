//
//  GitIdentitySwitcherView.swift
//  GitHalls
//

import Foundation
import SwiftUI

struct GitIdentitySwitcherView: View {
    @Bindable var viewModel: RepositoryViewModel
    @State private var pendingIdentity: GitIdentity?
    @State private var fixRemoteURL = false
    @State private var showTokenField = false
    @State private var githubToken = ""
    @State private var isSavingToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let current = viewModel.currentIdentity {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(current.name) <\(current.email)>")
                        .font(.caption)
                    Text(viewModel.hasLocalIdentityOverride ? "Local override for this repo" : "Using global default")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                Divider()
            }

            List(viewModel.savedIdentities) { identity in
                Button {
                    pendingIdentity = identity
                    fixRemoteURL = !identity.githubUsername.isEmpty
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(identity.label.isEmpty ? identity.name : identity.label)
                            Text(identity.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isActive(identity) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 120, maxHeight: 240)

            if let pendingIdentity {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if !pendingIdentity.githubUsername.isEmpty {
                        Toggle("Also fix remote URL for this account", isOn: $fixRemoteURL)
                            .font(.caption)

                        DisclosureGroup("Save GitHub token (fixes auth errors)", isExpanded: $showTokenField) {
                            VStack(alignment: .leading, spacing: 4) {
                                SecureField("Personal Access Token", text: $githubToken)
                                    .textFieldStyle(.roundedBorder)
                                Text("Stored by git's own credential helper for \(pendingIdentity.githubUsername)@github.com — GitHalls doesn't keep a copy. Needed once per account, if push/pull/fetch fails with an authentication error.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption)
                    }
                    Button(viewModel.isSwitchingIdentity || isSavingToken ? "Applying…" : "Use \(pendingIdentity.label.isEmpty ? pendingIdentity.name : pendingIdentity.label)") {
                        let identity = pendingIdentity
                        let fix = fixRemoteURL
                        let token = githubToken
                        Task {
                            if !token.isEmpty, !identity.githubUsername.isEmpty {
                                isSavingToken = true
                                let saved = await viewModel.saveGitHubToken(token, forUsername: identity.githubUsername)
                                isSavingToken = false
                                guard saved else { return }
                            }
                            await viewModel.setIdentity(identity, fixRemoteURL: fix)
                            self.pendingIdentity = nil
                            githubToken = ""
                            showTokenField = false
                        }
                    }
                    .disabled(viewModel.isSwitchingIdentity || isSavingToken)
                }
                .padding(10)
            }

            Divider()
            Text("Switching identity changes commit authorship. Push/fetch authenticate separately — use \"Save GitHub token\" above if they fail with an auth error.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(10)
        }
        .frame(width: 300)
        .task {
            viewModel.reloadSavedIdentities()
        }
    }

    private func isActive(_ identity: GitIdentity) -> Bool {
        guard let current = viewModel.currentIdentity else { return false }
        return current.name == identity.name && current.email == identity.email
    }
}
