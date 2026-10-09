//
//  JiraSettingsView.swift
//  GitHalls
//

import SwiftUI

struct JiraSettingsView: View {
    @State private var site = JiraPreferences.site?.absoluteString ?? ""
    @State private var email = JiraPreferences.email
    @State private var token = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false

    @AppStorage(IssueLinkPreferences.postCommitsKey) private var postCommits = true
    @AppStorage(IssueLinkPreferences.addKeyToCommitsKey) private var addKeyToCommits = true
    @AppStorage(IssueLinkPreferences.offerMovesKey) private var offerMoves = true
    @AppStorage(IssueLinkPreferences.offerTimerKey) private var offerTimer = true

    var body: some View {
        Form {
            Section("Jira Connection") {
                TextField("Site", text: $site, prompt: Text("https://your-domain.atlassian.net"))
                TextField("Email", text: $email)
                SecureField("API Token", text: $token, prompt: Text(JiraCredentialsStore.isConfigured ? "•••••••• (unchanged)" : ""))
            }

            Section {
                Toggle("Post pushed commits as a comment on the issue", isOn: $postCommits)
                Toggle("Add the issue key to commit messages", isOn: $addKeyToCommits)
                Toggle("Offer to move the issue when its pull request opens or merges", isOn: $offerMoves)
                Toggle("Offer to start the Clockify timer when switching to an issue's branch", isOn: $offerTimer)
                PullRequestFlowEditor()
                    .disabled(!offerMoves)
            } header: {
                Text("Branches")
            } footer: {
                Text("A branch belongs to an issue when its name contains the key, like feature/SWEB-6851-pdf.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    Task { await testAndSave() }
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting || site.isEmpty || email.isEmpty)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                }
            }
        }
        .padding(20)
        .frame(width: SettingsLayout.width)
        .frame(minHeight: SettingsLayout.minHeight)
    }

    private func testAndSave() async {
        guard let siteURL = normalizedSiteURL(site) else {
            statusMessage = "Invalid site URL."
            statusIsError = true
            return
        }

        let effectiveToken = token.isEmpty ? JiraCredentialsStore.current?.token : token
        guard let effectiveToken, !effectiveToken.isEmpty else {
            statusMessage = "API token required."
            statusIsError = true
            return
        }

        isTesting = true
        defer { isTesting = false }

        let credentials = JiraCredentials(site: siteURL, email: email, token: effectiveToken)
        do {
            let (_, displayName) = try await JiraClient(credentials: credentials).myself()
            try JiraCredentialsStore.save(site: siteURL, email: email, token: effectiveToken)
            statusMessage = "Connected as \(displayName)."
            statusIsError = false
            token = ""
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func normalizedSiteURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }
}

#Preview {
    JiraSettingsView()
}

/// The table that says what a pull request into each branch means for its
/// issue. Read top to bottom as the team's flow: a later line is a later stage,
/// and the app never offers to go back up it.
private struct PullRequestFlowEditor: View {
    @State private var rules = PullRequestFlowStore.rules

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When a pull request…").font(.callout).foregroundStyle(.secondary)

            ForEach($rules) { $rule in
                HStack(spacing: 6) {
                    Text("into").foregroundStyle(.secondary)
                    TextField("branch", text: $rule.base, prompt: Text("dev"))
                        .frame(width: 110)
                    Picker("Event", selection: $rule.event) {
                        ForEach(PullRequestEvent.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Text("offer").foregroundStyle(.secondary)
                    TextField("status", text: $rule.status, prompt: Text("automatic"))
                    Button {
                        rules.removeAll { $0.id == rule.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("Remove this line")
                }
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Add Line") {
                    rules.append(PullRequestRule(base: "", event: .merged, status: ""))
                }
                Button("Restore Defaults") { rules = PullRequestFlowStore.safeDefaults }
                    .disabled(rules == PullRequestFlowStore.safeDefaults)
            }

            Text("Branch: a name like dev or origin/homologacao, * for any, or default for the repository's main branch. "
                 + "Status: as it reads on your board; empty picks a review status, or a done one for a merge. "
                 + "Lines go in the order of your flow.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: rules) { _, new in PullRequestFlowStore.rules = new }
    }
}
