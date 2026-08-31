//
//  ConventionalCommitType.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 31/08/26.
//

import Foundation

enum ConventionalCommitType: String, CaseIterable, Identifiable {
    case feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert

    var id: String { rawValue }

    var description: String {
        switch self {
        case .feat: "A new feature for the user"
        case .fix: "A bug fix"
        case .docs: "Documentation only changes"
        case .style: "Changes that don't affect code meaning (formatting, whitespace)"
        case .refactor: "A code change that neither fixes a bug nor adds a feature"
        case .perf: "A code change that improves performance"
        case .test: "Adding or correcting tests"
        case .build: "Changes to the build system or external dependencies"
        case .ci: "Changes to CI configuration files and scripts"
        case .chore: "Other changes that don't modify src or test files"
        case .revert: "Reverts a previous commit"
        }
    }
}
