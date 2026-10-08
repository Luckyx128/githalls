//
//  GeneralSettingsView.swift
//  GitHalls
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AutoFetch.enabledKey) private var fetchAutomatically = true

    var body: some View {
        Form {
            Toggle("Fetch automatically", isOn: $fetchAutomatically)
            Text("Checks the remote every 5 minutes and when GitHalls comes to the front, so Pull and Push counts stay current. Never asks for a password; failures are silent.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.width)
        .frame(minHeight: SettingsLayout.minHeight)
    }
}
