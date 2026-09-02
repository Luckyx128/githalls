//
//  GitError.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation

enum GitError: LocalizedError {
    case failedToLaunch(underlying: Error)
    case gitNotFound
    case commandFailed(exitCode: Int32, message: String)
    case invalidRemoteURL

    var errorDescription: String? {
        switch self {
        case .failedToLaunch(let underlying):
            "Couldn't launch git: \(underlying.localizedDescription)"
        case .gitNotFound:
            "git was not found. Make sure it's installed and on your PATH."
        case .commandFailed(_, let message):
            Self.friendlyMessage(forRawGitError: message)
        case .invalidRemoteURL:
            "Couldn't determine the GitHub repository from the remote URL."
        }
    }

    private static func friendlyMessage(forRawGitError message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "git command failed." }

        if trimmed.contains("Device not configured") || trimmed.contains("terminal prompts disabled") {
            return "No saved credentials for this GitHub account on this Mac, so git can't authenticate. Add a Personal Access Token for this identity (Git Identities), or run this command once in Terminal to sign in.\n\n\(trimmed)"
        }
        if trimmed.contains("Repository not found") {
            return "GitHub reports this repository doesn't exist — which is also what it says for a private repo the current account can't see. Check the selected identity has access, or add a token for the right account.\n\n\(trimmed)"
        }
        if trimmed.contains("Authentication failed") || trimmed.contains("403") {
            return "GitHub rejected the credentials for this account. The token may be expired, missing the repo scope, or saved for the wrong account.\n\n\(trimmed)"
        }
        if trimmed.contains("Permission denied (publickey)") {
            return "GitHub didn't recognize this Mac's SSH key for this account. Check the right key is loaded (ssh-add -l) and added to the account on GitHub.\n\n\(trimmed)"
        }
        return trimmed
    }
}
