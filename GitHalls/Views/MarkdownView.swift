//
//  MarkdownView.swift
//  GitHalls
//

import SwiftUI

/// Lays out parsed Markdown blocks.
///
/// The parsing is all in `MarkdownParser`, which is why this is only sizes and
/// spacing: the decisions worth testing are not in here.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let spans):
            Text(Self.attributed(spans))
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 8 : 4)

        case .paragraph(let spans):
            Text(Self.attributed(spans))

        case .listItem(let spans, _, let marker):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(Self.attributed(spans))
            }
            .padding(.leading, 8)

        case .quote(let spans):
            HStack(alignment: .top, spacing: 8) {
                // The bar is the quote; a box would compete with the code blocks.
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 3)
                Text(Self.attributed(spans))
                    .foregroundStyle(.secondary)
            }

        case .code(let text, _):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

        case .table(let rows):
            // Monospaced so the pipes line up into columns.
            Text(rows.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

        case .rule:
            Divider()
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }

    private static func attributed(_ spans: [MarkdownSpan]) -> AttributedString {
        var result = AttributedString()

        for span in spans {
            var piece = AttributedString(span.text)

            switch span.style {
            case .plain:
                break
            case .bold:
                piece.inlinePresentationIntent = .stronglyEmphasized
            case .italic:
                piece.inlinePresentationIntent = .emphasized
            case .code:
                piece.inlinePresentationIntent = .code
            case .link(let url):
                piece.link = url
                piece.underlineStyle = .single
            }

            result.append(piece)
        }

        return result
    }
}
