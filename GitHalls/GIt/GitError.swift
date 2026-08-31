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
            message.isEmpty ?  "git command failed." : message
        case .invalidRemoteURL:
            "Couldn't determine the GitHub repository from the remote URL."
        }
    }
}
