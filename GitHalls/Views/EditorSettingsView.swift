//
//  EditorSettingsView.swift
//  GitHalls
//

import SwiftUI

/// Where "Open in → Neovim" and the other command-line editors run.
struct EditorSettingsView: View {
    /// Empty means "not picked": the first installed terminal is used.
    @AppStorage(ExternalEditors.preferredTerminalKey) private var preferredTerminal = ""

    private let terminals = ExternalEditors.installedTerminals

    var body: some View {
        Form {
            Picker("Terminal for Neovim / Vim", selection: $preferredTerminal) {
                Text("Automatic").tag("")
                ForEach(terminals) { terminal in
                    Text(terminal.name).tag(terminal.bundleIdentifier)
                }
            }
            Text("Command-line editors have no window of their own, so GitHalls opens them in this terminal.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
