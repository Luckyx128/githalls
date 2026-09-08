//
//  ExternalEditor.swift
//  GitHalls
//

import AppKit
import Foundation

/// An editor this Mac can hand a file to.
struct ExternalEditor: Identifiable, Hashable {
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
        ExternalEditor(bundleIdentifier: "com.microsoft.VSCode", name: "Visual Studio Code"),
        ExternalEditor(bundleIdentifier: "com.microsoft.VSCodeInsiders", name: "VS Code Insiders"),
        ExternalEditor(bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        ExternalEditor(bundleIdentifier: "dev.zed.Zed", name: "Zed"),
        ExternalEditor(bundleIdentifier: "com.jetbrains.WebStorm", name: "WebStorm"),
        ExternalEditor(bundleIdentifier: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        ExternalEditor(bundleIdentifier: "com.jetbrains.intellij.ce", name: "IntelliJ IDEA CE"),
        ExternalEditor(bundleIdentifier: "com.jetbrains.pycharm", name: "PyCharm"),
        ExternalEditor(bundleIdentifier: "com.jetbrains.PhpStorm", name: "PhpStorm"),
        ExternalEditor(bundleIdentifier: "com.jetbrains.goland", name: "GoLand"),
        ExternalEditor(bundleIdentifier: "com.jetbrains.rider", name: "Rider"),
        ExternalEditor(bundleIdentifier: "com.google.android.studio", name: "Android Studio"),
        ExternalEditor(bundleIdentifier: "com.sublimetext.4", name: "Sublime Text"),
        ExternalEditor(bundleIdentifier: "com.panic.Nova", name: "Nova"),
        ExternalEditor(bundleIdentifier: "com.barebones.bbedit", name: "BBEdit"),
        ExternalEditor(bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode")
    ]

    /// Only the ones actually on this Mac, in the order above. Looked up once:
    /// apps do not come and go while the window is open, and this is read every
    /// time a context menu opens.
    static let installed: [ExternalEditor] = known.filter {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil
    }

    static func open(_ fileURL: URL, with editor: ExternalEditor) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) else {
            // Uninstalled since the list was built; the system's own choice
            // still beats doing nothing.
            NSWorkspace.shared.open(fileURL)
            return
        }

        NSWorkspace.shared.open([fileURL], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }
}
