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

    var body: some View {
        Form {
            Section("Jira Connection") {
                TextField("Site", text: $site, prompt: Text("https://your-domain.atlassian.net"))
                TextField("Email", text: $email)
                SecureField("API Token", text: $token, prompt: Text(JiraCredentialsStore.isConfigured ? "•••••••• (unchanged)" : ""))
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
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
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
