//
//  DiffTextTheme.swift
//  GitHalls
//
//  Colors, fonts and paragraph metrics for the NSTextView-backed diff renderer.
//

import AppKit

/// Which Highlightr colour scheme, font and size to render with.
nonisolated struct DiffTheme: Equatable, Sendable {
    /// Bundled Highlightr theme name.
    let highlightrThemeName: String
    let fontID: String
    let fontSize: CGFloat

    static let light = DiffTheme(highlightrThemeName: CodeAppearance.defaultLightTheme,
                                 fontID: CodeAppearance.defaultFontID,
                                 fontSize: CGFloat(CodeAppearance.defaultSize))
    static let dark = DiffTheme(highlightrThemeName: CodeAppearance.defaultDarkTheme,
                                fontID: CodeAppearance.defaultFontID,
                                fontSize: CGFloat(CodeAppearance.defaultSize))

    var font: NSFont { CodeFontCatalog.font(id: fontID, size: fontSize) }

    /// Changes whenever anything that affects rendering changes.
    var cacheKey: String { "\(highlightrThemeName)|\(fontID)|\(fontSize)" }
}

nonisolated struct DiffTextTheme {
    let scheme: DiffTheme
    /// Decided by the theme background's luminance, not the system appearance.
    let isDark: Bool

    let viewBackground: NSColor
    let baseText: NSColor
    let hunkHeaderText: NSColor
    let hunkHeaderBackground: NSColor
    let additionBackground: NSColor
    let deletionBackground: NSColor
    let gutterBackground: NSColor
    let gutterText: NSColor
    let gutterSeparator: NSColor
    let additionMarker: NSColor
    let deletionMarker: NSColor

    let font: NSFont
    let headerFont: NSFont
    let lineHeightMultiple: CGFloat

    /// Stable identity for cache keys — changes only when the visible styling changes.
    var identity: String { scheme.cacheKey }

    func lineBackground(for kind: DiffLine.Kind) -> NSColor? {
        switch kind {
        case .addition: additionBackground
        case .deletion: deletionBackground
        case .hunkHeader: hunkHeaderBackground
        case .context: nil
        }
    }

    /// Blend of `from` toward `to` by `amount` (0...1), opaque.
    private static func blend(_ from: NSColor, _ to: NSColor, _ amount: CGFloat) -> NSColor {
        let a = from.usingColorSpace(.sRGB) ?? from
        let b = to.usingColorSpace(.sRGB) ?? to
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * amount,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount,
                       alpha: 1)
    }

    static func make(_ scheme: DiffTheme) -> DiffTextTheme {
        let font = scheme.font
        let headerFont = CodeFontCatalog.font(id: scheme.fontID, size: max(scheme.fontSize - 1, 8))

        let colors = CodeThemeColorStore.shared.colors(for: scheme.highlightrThemeName)
        let bgRGB = colors.background ?? CodeThemeColors.RGB(r: 1, g: 1, b: 1)
        let isDark = CodeThemeCatalog.isDarkBackground(
            luminance: CodeThemeCatalog.luminance(red: bgRGB.r, green: bgRGB.g, blue: bgRGB.b))
        let textRGB = colors.text ?? (isDark ? CodeThemeColors.RGB(r: 0.88, g: 0.88, b: 0.88)
                                             : CodeThemeColors.RGB(r: 0.13, g: 0.13, b: 0.13))

        let background = NSColor(srgbRed: bgRGB.r, green: bgRGB.g, blue: bgRGB.b, alpha: 1)
        let text = NSColor(srgbRed: textRGB.r, green: textRGB.g, blue: textRGB.b, alpha: 1)

        // Tints stay translucent overlays so they read on any background.
        let addition = isDark
            ? NSColor(srgbRed: 0.30, green: 0.85, blue: 0.40, alpha: 0.16)
            : NSColor(srgbRed: 0.22, green: 0.72, blue: 0.30, alpha: 0.15)
        let deletion = isDark
            ? NSColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 0.16)
            : NSColor(srgbRed: 0.90, green: 0.24, blue: 0.24, alpha: 0.14)
        let hunk = isDark
            ? NSColor(srgbRed: 0.35, green: 0.55, blue: 1.0, alpha: 0.16)
            : NSColor(srgbRed: 0.20, green: 0.45, blue: 0.90, alpha: 0.09)

        return DiffTextTheme(
            scheme: scheme,
            isDark: isDark,
            viewBackground: background,
            baseText: text,
            hunkHeaderText: blend(background, text, 0.62),
            hunkHeaderBackground: hunk,
            additionBackground: addition,
            deletionBackground: deletion,
            gutterBackground: blend(background, text, 0.05),
            gutterText: blend(background, text, 0.45),
            gutterSeparator: blend(background, text, 0.14),
            additionMarker: isDark ? NSColor(srgbRed: 0.40, green: 0.85, blue: 0.45, alpha: 1)
                                   : NSColor(srgbRed: 0.16, green: 0.60, blue: 0.24, alpha: 1),
            deletionMarker: isDark ? NSColor(srgbRed: 1.0, green: 0.45, blue: 0.45, alpha: 1)
                                   : NSColor(srgbRed: 0.80, green: 0.18, blue: 0.18, alpha: 1),
            font: font,
            headerFont: headerFont,
            lineHeightMultiple: 1.18
        )
    }
}
