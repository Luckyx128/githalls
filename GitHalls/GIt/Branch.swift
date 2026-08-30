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

    var id: String { name }
}
