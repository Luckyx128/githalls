//
//  ExternalEditor.swift
//  GitHalls
//

import AppKit
import Foundation

/// An editor this Mac can hand a file to.
struct ExternalEditor: Identifiable, Hashable {
    enum Kind: Hashable {
        case application(bundleIdentifier: String)
        /// A command-line editor. It has no window of its own, so it is run
        /// inside a terminal.
        case terminal(command: String)
    }

    let kind: Kind
    let name: String

    var id: String {
        switch kind {
        case .application(let bundleIdentifier): bundleIdentifier
        case .terminal(let command): "terminal:\(command)"
        }
    }
}

/// A terminal a command-line editor can be run in.
struct TerminalApp: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

enum ExternalEditors {
    /// Identified by bundle id rather than by a command on PATH: `code`, `zed`
    /// and the JetBrains launchers are opt-in extras the user may never have
    /// installed, while the app itself is always there to be found.
    ///
    /// A wrong or renamed identifier costs one missing menu entry and nothing
    /// else, which is why guessing at the list is safe.
    static let known: [ExternalEditor] = [
        app("com.microsoft.VSCode", "Visual Studio Code"),
        app("com.microsoft.VSCodeInsiders", "VS Code Insiders"),
        app("com.todesktop.230313mzl4w4u92", "Cursor"),
        app("dev.zed.Zed", "Zed"),
        app("com.jetbrains.WebStorm", "WebStorm"),
        app("com.jetbrains.intellij", "IntelliJ IDEA"),
        app("com.jetbrains.intellij.ce", "IntelliJ IDEA CE"),
        app("com.jetbrains.pycharm", "PyCharm"),
        app("com.jetbrains.PhpStorm", "PhpStorm"),
        app("com.jetbrains.goland", "GoLand"),
        app("com.jetbrains.rider", "Rider"),
        app("com.google.android.studio", "Android Studio"),
        app("com.sublimetext.4", "Sublime Text"),
        app("com.panic.Nova", "Nova"),
        app("com.barebones.bbedit", "BBEdit"),
        app("com.apple.dt.Xcode", "Xcode"),
        ExternalEditor(kind: .terminal(command: "nvim"), name: "Neovim"),
        ExternalEditor(kind: .terminal(command: "vim"), name: "Vim")
    ]

    /// Only the ones actually on this Mac, in the order above. Looked up once:
    /// apps do not come and go while the window is open, and this is read every
    /// time a context menu opens.
    static let installed: [ExternalEditor] = known.filter { editor in
        switch editor.kind {
        case .application(let bundleIdentifier):
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        case .terminal(let command):
            resolvedCommands[command] != nil
        }
    }

    /// Hands every file to the editor in one go, so a terminal editor gets one
    /// window with a tab per file rather than a window per file.
    static func open(_ fileURLs: [URL], in directory: URL, with editor: ExternalEditor) {
        guard !fileURLs.isEmpty else { return }

        switch editor.kind {
        case .application(let bundleIdentifier):
            guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                // Uninstalled since the list was built; the system's own choice
                // still beats doing nothing.
                fileURLs.forEach { NSWorkspace.shared.open($0) }
                return
            }
            NSWorkspace.shared.open(fileURLs, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())

        case .terminal(let command):
            guard let executable = resolvedCommands[command] else { return }
            openInTerminal(launchScript(executable: executable, directory: directory, files: fileURLs))
        }
    }

    // MARK: - Terminal editors

    /// Every one of these runs a `.command` file when asked to open one. The
    /// order is the fallback when the user has not picked one in Settings.
    static let knownTerminals: [TerminalApp] = [
        TerminalApp(bundleIdentifier: "com.googlecode.iterm2", name: "iTerm"),
        TerminalApp(bundleIdentifier: "dev.warp.Warp-Stable", name: "Warp"),
        TerminalApp(bundleIdentifier: "com.apple.Terminal", name: "Terminal")
    ]

    static var installedTerminals: [TerminalApp] {
        knownTerminals.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil }
    }

    /// Read through `@AppStorage` by the settings view, so the key lives here once.
    static let preferredTerminalKey = "preferredTerminal"

    /// The terminal picked in Settings, or the first installed one when nothing
    /// was picked or the pick has since been uninstalled.
    static var preferredTerminal: TerminalApp? {
        let installed = installedTerminals
        let picked = UserDefaults.standard.string(forKey: preferredTerminalKey)
        return installed.first { $0.bundleIdentifier == picked } ?? installed.first
    }

    /// A `.command` script is the one thing every terminal knows how to run
    /// without Automation permissions. It removes itself as its first act.
    static func launchScript(executable: String, directory: URL, files: [URL]) -> String {
        let arguments = files.map { shellQuoted($0.path) }.joined(separator: " ")
        return """
        #!/bin/sh
        rm -f "$0"
        cd \(shellQuoted(directory.path)) || exit 1
        exec \(shellQuoted(executable)) -p \(arguments)

        """
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func openInTerminal(_ script: String) {
        let scriptURL = FileManager.default.temporaryDirectory
            .appending(path: "GitHalls-\(UUID().uuidString).command")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            return
        }

        guard let terminal = preferredTerminal
            .flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) }) else {
            NSWorkspace.shared.open(scriptURL)
            return
        }
        NSWorkspace.shared.open([scriptURL], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Absolute paths for the terminal editors, keyed by command.
    ///
    /// An app launched from Finder does not get the PATH the user's shell
    /// builds, so a `nvim` living in `~/.local/bin` or a hand-unpacked folder is
    /// invisible to it. The usual install locations are checked first; only a
    /// miss pays for asking the login shell.
    private static let resolvedCommands: [String: String] = {
        let commands = known.compactMap { editor -> String? in
            if case .terminal(let command) = editor.kind { return command }
            return nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin"]

        var resolved: [String: String] = [:]
        for command in commands {
            if let path = commonDirectories.map({ "\($0)/\(command)" })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                resolved[command] = path
            }
        }

        let missing = commands.filter { resolved[$0] == nil }
        if !missing.isEmpty {
            for path in loginShellLookup(missing) {
                let command = URL(fileURLWithPath: path).lastPathComponent
                if missing.contains(command), resolved[command] == nil {
                    resolved[command] = path
                }
            }
        }
        return resolved
    }()

    /// `command -v` reads the same in sh, zsh, bash and fish. Bounded, because a
    /// shell config that waits on something must not freeze a context menu.
    private static func loginShellLookup(_ commands: [String]) -> [String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", commands.map { "command -v \($0)" }.joined(separator: "; ")]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func app(_ bundleIdentifier: String, _ name: String) -> ExternalEditor {
        ExternalEditor(kind: .application(bundleIdentifier: bundleIdentifier), name: name)
    }
}
