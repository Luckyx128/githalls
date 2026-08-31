//
//  QuickActions.swift
//  GitHalls
//

import Foundation
import AppKit

enum QuickActions {
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openInTerminal(_ url: URL) {
        launch("/usr/bin/open", arguments: ["-a", "Terminal", url.path])
    }
 
    static func openInEditor(_ url: URL) async {
        if await isCommandAvailable("code") {
            launch("/usr/bin/env", arguments: ["code", url.path])
        } else {
            launch("/usr/bin/open", arguments: [url.path])
        }
    }

    private static func launch(_ executablePath: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try? process.run()
    }

    private static func isCommandAvailable(_ command: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["which", command]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
