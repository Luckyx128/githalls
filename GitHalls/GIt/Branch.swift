//
//  Branch.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 30/08/26.
//

import Foundation

struct Branch: Identifiable, Hashable {
    let name: String
    let isCurrent: Bool
    let isRemote: Bool

    var id: String { (isRemote ? "remote:" : "local:") + name }
}

extension Branch {
    static func remoteShortName(from remoteBranchName: String) -> String {
        guard let slashIndex = remoteBranchName.firstIndex(of: "/") else { return remoteBranchName }
        return String(remoteBranchName[remoteBranchName.index(after: slashIndex)...])
    }
}
