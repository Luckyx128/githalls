//
//  DiffTextTheme.swift
//  GitHalls
//
//  Colors, fonts and paragraph metrics for the NSTextView-backed diff renderer.
//

import AppKit

/// Which Highlightr colour scheme to use. Derived from the SwiftUI environment.
nonisolated enum DiffTheme: Equatable {
    case light
    case dark

    /// Bundled Highlightr theme name — `xcode` / `xcode-dark` to match the native editor.
    var highlightrThemeName: String {
        switch self {
        case .light: "xcode"
        case .dark: "xcode-dark"
        }
    }
}

nonisolated struct DiffTextTheme {
    let scheme: DiffTheme

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
    var identity: String { scheme == .dark ? "dark" : "light" }

    func lineBackground(for kind: DiffLine.Kind) -> NSColor? {
        switch kind {
        case .addition: additionBackground
        case .deletion: deletionBackground
        case .hunkHeader: hunkHeaderBackground
        case .context: nil
        }
    }

    static func make(_ scheme: DiffTheme) -> DiffTextTheme {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let headerFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        switch scheme {
        case .light:
            return DiffTextTheme(
                scheme: .light,
                viewBackground: NSColor(calibratedWhite: 1.0, alpha: 1.0),
                baseText: NSColor(calibratedWhite: 0.13, alpha: 1.0),
                hunkHeaderText: NSColor(calibratedWhite: 0.40, alpha: 1.0),
                hunkHeaderBackground: NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.90, alpha: 0.09),
                additionBackground: NSColor(calibratedRed: 0.22, green: 0.72, blue: 0.30, alpha: 0.15),
                deletionBackground: NSColor(calibratedRed: 0.90, green: 0.24, blue: 0.24, alpha: 0.14),
                gutterBackground: NSColor(calibratedWhite: 0.965, alpha: 1.0),
                gutterText: NSColor(calibratedWhite: 0.58, alpha: 1.0),
                gutterSeparator: NSColor(calibratedWhite: 0.86, alpha: 1.0),
                additionMarker: NSColor(calibratedRed: 0.16, green: 0.60, blue: 0.24, alpha: 1.0),
                deletionMarker: NSColor(calibratedRed: 0.80, green: 0.18, blue: 0.18, alpha: 1.0),
                font: font,
                headerFont: headerFont,
                lineHeightMultiple: 1.18
            )
        case .dark:
            return DiffTextTheme(
                scheme: .dark,
                viewBackground: NSColor(calibratedRed: 0.121, green: 0.125, blue: 0.149, alpha: 1.0),
                baseText: NSColor(calibratedWhite: 0.88, alpha: 1.0),
                hunkHeaderText: NSColor(calibratedWhite: 0.62, alpha: 1.0),
                hunkHeaderBackground: NSColor(calibratedRed: 0.35, green: 0.55, blue: 1.0, alpha: 0.16),
                additionBackground: NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.40, alpha: 0.16),
                deletionBackground: NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: 0.16),
                gutterBackground: NSColor(calibratedRed: 0.145, green: 0.149, blue: 0.176, alpha: 1.0),
                gutterText: NSColor(calibratedWhite: 0.48, alpha: 1.0),
                gutterSeparator: NSColor(calibratedWhite: 0.30, alpha: 1.0),
                additionMarker: NSColor(calibratedRed: 0.40, green: 0.85, blue: 0.45, alpha: 1.0),
                deletionMarker: NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.45, alpha: 1.0),
                font: font,
                headerFont: headerFont,
                lineHeightMultiple: 1.18
            )
        }
    }
}
