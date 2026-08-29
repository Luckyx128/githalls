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
        if line.kind == .hunkHeader {
            Text(line.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.08))
        } else {
            HStack(spacing: 8) {
                Text(gutterCharacter)
                    .frame(width: 12)
                    .foregroundStyle(gutterColor)
                    .fontWeight(.bold)

                Text(line.oldLineNumber.map(String.init) ?? "")
                    .frame(width: 32, alignment: .trailing)
                Text(line.newLineNumber.map(String.init) ?? "")
                    .frame(width: 32, alignment: .trailing)
                Text(SyntaxHighlighter.highlight(line.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(backgroundColor)
        }
    }

    private var gutterCharacter: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "-"
        default: " "
        }
    }

    private var gutterColor: Color {
        switch line.kind {
        case .addition: .green
        case .deletion: .red
        default: .clear
        }
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .addition: .green.opacity(0.15)
        case .deletion: .red.opacity(0.15)
        case .context: .clear
        case .hunkHeader: .clear // não é mais usado nesse branch, mas o switch continua exaustivo
        }
    }
}
