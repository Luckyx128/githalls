//
//  ClockifySettingsView.swift
//  GitHalls
//

import SwiftUI

struct ClockifySettingsView: View {
    @Bindable var clockify: ClockifyViewModel

    @State private var apiKey = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Clockify Connection") {
                SecureField("API Key", text: $apiKey, prompt: Text(ClockifyCredentialsStore.isConfigured ? "•••••••• (unchanged)" : ""))
                Link("Get your API key in Clockify › Preferences › Advanced",
                     destination: URL(string: "https://app.clockify.me/manage-api-keys")!)
                    .font(.callout)
            }

            if clockify.workspaces.count > 1 {
                Section("Default Workspace") {
                    Picker("Workspace", selection: Binding(
                        get: { clockify.workspaceID ?? "" },
                        set: { id in Task { await clockify.selectWorkspace(id) } }
                    )) {
                        ForEach(clockify.workspaces) { Text($0.name).tag($0.id) }
                    }
                }
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
                .disabled(isTesting || (apiKey.isEmpty && !ClockifyCredentialsStore.isConfigured))

                if ClockifyCredentialsStore.isConfigured {
                    Button("Disconnect", role: .destructive) {
                        ClockifyCredentialsStore.forget()
                        clockify.reset()
                        statusMessage = "Disconnected."
                        statusIsError = false
                    }
                }

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
        .task { await clockify.load() }
    }

    private func testAndSave() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveKey = key.isEmpty ? ClockifyCredentialsStore.apiKey : key
        guard let effectiveKey, !effectiveKey.isEmpty else {
            statusMessage = "API key required."
            statusIsError = true
            return
        }

        isTesting = true
        defer { isTesting = false }

        do {
            let user = try await ClockifyClient(apiKey: effectiveKey).user()
            try ClockifyCredentialsStore.save(apiKey: effectiveKey)
            clockify.reset()
            await clockify.load()
            statusMessage = "Connected as \(user.name)."
            statusIsError = false
            apiKey = ""
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }
}
