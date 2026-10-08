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

    @AppStorage(CodeAppearance.lightThemeKey) private var lightTheme = CodeAppearance.defaultLightTheme
    @AppStorage(CodeAppearance.darkThemeKey) private var darkTheme = CodeAppearance.defaultDarkTheme
    @AppStorage(CodeAppearance.fontKey) private var fontID = CodeAppearance.defaultFontID
    @AppStorage(CodeAppearance.sizeKey) private var fontSize = CodeAppearance.defaultSize
    @Environment(\.colorScheme) private var colorScheme

    private var codeTheme: DiffTheme {
        CodeAppearance.theme(isDark: colorScheme == .dark, lightTheme: lightTheme, darkTheme: darkTheme,
                             fontID: fontID, size: fontSize)
    }

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
            Text(attributed(spans))
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 8 : 4)

        case .paragraph(let spans):
            Text(attributed(spans))

        case .listItem(let spans, _, let marker):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(attributed(spans))
            }
            .padding(.leading, 8)

        case .quote(let spans):
            HStack(alignment: .top, spacing: 8) {
                // The bar is the quote; a box would compete with the code blocks.
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 3)
                Text(attributed(spans))
                    .foregroundStyle(.secondary)
            }

        case .code(let text, let language):
            codeBlock(text, language: language)

        case .table(let rows):
            // Monospaced so the pipes line up into columns.
            codeBlock(rows.joined(separator: "\n"), language: nil)

        case .rule:
            Divider()
        }
    }

    /// Fenced code in the selected code theme, font and size; plain text when the language is unknown.
    private func codeBlock(_ text: String, language: String?) -> some View {
        let theme = codeTheme
        let colors = CodeThemeColorStore.shared.colors(for: theme.highlightrThemeName)
        let background = Self.color(colors.background) ?? Color(nsColor: .textBackgroundColor)
        let foreground = Self.color(colors.text) ?? Color.primary
        let lang = language?.trimmingCharacters(in: .whitespaces).lowercased()
        let lines = DiffSyntaxHighlighter.shared.highlightedLines(
            for: text, language: (lang?.isEmpty ?? true) ? nil : lang, theme: theme)

        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            line.enumerateAttributes(in: NSRange(location: 0, length: line.length)) { attrs, range, _ in
                var piece = AttributedString(line.attributedSubstring(from: range).string)
                if let ns = attrs[.foregroundColor] as? NSColor { piece.foregroundColor = Color(nsColor: ns) }
                result.append(piece)
            }
        }

        return Text(result)
            .font(Font(theme.font))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }

    private static func color(_ rgb: CodeThemeColors.RGB?) -> Color? {
        rgb.map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b) }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }

    private func attributed(_ spans: [MarkdownSpan]) -> AttributedString {
        let theme = codeTheme
        let colors = CodeThemeColorStore.shared.colors(for: theme.highlightrThemeName)
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
                piece.font = Font(theme.font)
                if let bg = Self.color(colors.background) { piece.backgroundColor = bg }
                if let fg = Self.color(colors.text) { piece.foregroundColor = fg }
            case .link(let url):
                piece.link = url
                piece.underlineStyle = .single
            }

            result.append(piece)
        }

        return result
    }
}
