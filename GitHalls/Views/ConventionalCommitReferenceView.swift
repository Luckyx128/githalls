//
//  ConventionalCommitReferenceView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 31/08/26.
//

import SwiftUI

struct ConventionalCommitReferenceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conventional Commits")
                .font(.headline)

            ForEach(ConventionalCommitType.allCases) { type in
                VStack(alignment: .leading, spacing: 1) {
                    Text(type.rawValue)
                        .font(.system(.body, design: .monospaced))
                        .bold()
                    Text(type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
