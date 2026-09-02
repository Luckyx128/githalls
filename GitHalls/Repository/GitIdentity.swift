//
//  GitIdentity.swift
//  GitHalls
//

import Foundation

struct GitIdentity: Codable, Identifiable, Equatable {
    let id: UUID
    var label: String          
    var name: String
    var email: String
    var githubUsername: String
}

enum GitIdentityStore {
    private static let key = "gitIdentities"

    static func load() -> [GitIdentity] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let identities = try? JSONDecoder().decode([GitIdentity].self, from: data)
        else { return [] }
        return identities
    }

    static func save(_ identities: [GitIdentity]) {
        guard let data = try? JSONEncoder().encode(identities) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func add(_ identity: GitIdentity) {
        var identities = load()
        identities.append(identity)
        save(identities)
    }

    static func remove(_ id: GitIdentity.ID) {
        save(load().filter { $0.id != id })
    }
}
