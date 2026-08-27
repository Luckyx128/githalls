//
//  DiffView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation
import SwiftUI

struct DiffView: View {
    let diff: FileDiff

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(diff.lines) { line in
                    DiffLineRow(line: line)
                }
            }
        }
    }
}

struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 8) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 32, alignment: .trailing)
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 32, alignment: .trailing)
            Text(line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(line.kind == .hunkHeader ? .secondary : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(backgroundColor)
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .addition: .green.opacity(0.15)
        case .deletion: .red.opacity(0.15)
        case .hunkHeader: .blue.opacity(0.08)
        case .context: .clear
        }
    }
}
