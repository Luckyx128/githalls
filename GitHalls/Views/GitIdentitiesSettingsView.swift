//
//  GitIdentitiesSettingsView.swift
//  GitHalls
//

import SwiftUI

struct GitIdentitiesSettingsView: View {
    @State private var identities: [GitIdentity] = GitIdentityStore.load()
    @State private var label = ""
    @State private var name = ""
    @State private var email = ""
    @State private var githubUsername = ""

    private let gitService = GitService()
    @State private var tokenEditingID: GitIdentity.ID?
    @State private var tokenInput = ""
    @State private var isSavingToken = false
    @State private var tokenStatus: [GitIdentity.ID: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                savedIdentitiesBox
                addIdentityBox
                note("Switching identity only changes who's recorded as the author on commits in the open repository — it does not affect push or fetch, which authenticate separately via SSH key or credential helper.")
                note("The GitHub Username field fixes the classic \"push denied to the wrong account\" error: it rewrites the repo's remote URL to embed that username, so the credential helper resolves a specific credential instead of a generic one for github.com. Click the key icon next to an identity to save a Personal Access Token for that account directly — no need to authenticate via Terminal or \"gh auth login\" first.")
            }
            .padding(20)
        }
        .frame(width: 460, height: 560)
    }

    // MARK: - Saved Identities

    private var savedIdentitiesBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved Identities")
                .font(.headline)

            if identities.isEmpty {
                Text("No identities saved yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(identities) { identity in
                        IdentityRow(
                            identity: identity,
                            gitService: gitService,
                            tokenEditingID: $tokenEditingID,
                            tokenInput: $tokenInput,
                            isSavingToken: $isSavingToken,
                            tokenStatus: $tokenStatus,
                            onDelete: {
                                GitIdentityStore.remove(identity.id)
                                identities = GitIdentityStore.load()
                            }
                        )
                        if identity.id != identities.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Add Identity

    private var addIdentityBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Identity")
                .font(.headline)

            labeledField("Label", text: $label, prompt: "Personal, Work…")
            labeledField("Name", text: $name)
            labeledField("Email", text: $email)
            labeledField("GitHub Username (optional)", text: $githubUsername, prompt: "used to fix remote URL / credential conflicts")

            Button("Add") {
                let identity = GitIdentity(
                    id: UUID(), label: label, name: name, email: email, githubUsername: githubUsername
                )
                GitIdentityStore.add(identity)
                identities = GitIdentityStore.load()
                label = ""
                name = ""
                email = ""
                githubUsername = ""
            }
            .disabled(label.isEmpty || name.isEmpty || email.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func labeledField(_ title: String, text: Binding<String>, prompt: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: text, prompt: prompt.map { Text($0) })
                .textFieldStyle(.roundedBorder)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Linha de identidade salva, incluindo o editor de token — separada em view
/// própria porque o corpo inteiro dentro de um `ForEach` ficava complexo
/// demais pro type-checker do SwiftUI resolver em tempo razoável.
private struct IdentityRow: View {
    let identity: GitIdentity
    let gitService: GitService
    @Binding var tokenEditingID: GitIdentity.ID?
    @Binding var tokenInput: String
    @Binding var isSavingToken: Bool
    @Binding var tokenStatus: [GitIdentity.ID: String]
    let onDelete: () -> Void

    private var isEditingToken: Bool { tokenEditingID == identity.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if isEditingToken {
                tokenEditor
            }
            if let status = tokenStatus[identity.id], !isEditingToken {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(status == "Saved." ? Color.secondary : Color.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.label.isEmpty ? identity.name : identity.label)
                Text("\(identity.name) <\(identity.email)>")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !identity.githubUsername.isEmpty {
                    Text("GitHub: \(identity.githubUsername)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if isEditingToken {
                    tokenEditingID = nil
                } else {
                    tokenEditingID = identity.id
                    tokenInput = ""
                }
            } label: {
                Image(systemName: "key")
            }
            .buttonStyle(.borderless)
            .disabled(identity.githubUsername.isEmpty)
            .help(identity.githubUsername.isEmpty ? "Set a GitHub Username first" : "Save a Personal Access Token for this account")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var tokenEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField("Personal Access Token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)
            Text("Stored by git's own credential helper for \(identity.githubUsername)@github.com — GitHalls doesn't keep a copy. Needs \"repo\" scope; if the account belongs to an org with SSO enforced, the token also needs to be authorized for that org.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button(isSavingToken ? "Saving…" : "Save Token", action: saveToken)
                    .disabled(tokenInput.isEmpty || isSavingToken)
                Button("Cancel") {
                    tokenEditingID = nil
                    tokenInput = ""
                }
            }
        }
        .padding(.top, 2)
    }

    private func saveToken() {
        let username = identity.githubUsername
        let token = tokenInput
        let id = identity.id
        Task {
            isSavingToken = true
            do {
                try await gitService.approveCredential(username: username, token: token)
                tokenStatus[id] = "Saved."
                tokenEditingID = nil
                tokenInput = ""
            } catch {
                tokenStatus[id] = error.localizedDescription
            }
            isSavingToken = false
        }
    }
}

#Preview {
    GitIdentitiesSettingsView()
}
