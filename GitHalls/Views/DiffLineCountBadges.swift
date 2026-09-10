//
//  DiffLineCountBadges.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 10/09/26.
//

import SwiftUI

/// How much a file changed, in the one form that reads at a glance.
struct DiffLineCountBadges: View {
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: 6) {
            if added > 0 {
                Text("+\(added)")
                    .foregroundStyle(.green)
            }
            if removed > 0 {
                Text("−\(removed)")
                    .foregroundStyle(.red)
            }
            if added == 0, removed == 0 {
                Text("no line changes")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .monospacedDigit()
    }
}
