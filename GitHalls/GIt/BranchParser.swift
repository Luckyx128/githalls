//
//  BranchParser.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 30/08/26.
//

import Foundation

enum BranchParser {
    static func parse(_ raw: String) -> [Branch] {
        raw.split(separator: "\n").compactMap { line -> Branch? in
            let isCurrent = line.hasPrefix("* ")
            let name = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            // Ignora o caso de "HEAD detached at ..." — não é uma branch de verdade.
            guard !name.isEmpty, !name.hasPrefix("(") else { return nil }
            return Branch(name: name, isCurrent: isCurrent)
        }
    }
}
