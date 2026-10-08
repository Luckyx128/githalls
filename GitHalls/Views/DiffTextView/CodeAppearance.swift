//
//  CodeAppearance.swift
//  GitHalls
//
//  User-selectable code theme, font and size for the diff view. Keys, defaults
//  and the pure helpers (name prettifying, font filtering, luminance) live here
//  so they can be tested without a UI.
//

import AppKit

nonisolated enum CodeAppearance {
    static let lightThemeKey = "codeThemeLight"
    static let darkThemeKey = "codeThemeDark"
    static let fontKey = "codeFont"
    static let sizeKey = "codeFontSize"

    static let defaultLightTheme = "xcode"
    static let defaultDarkTheme = "xcode-dark"
    static let defaultFontID = CodeFontCatalog.systemID
    static let defaultSize: Double = 12
    static let sizeRange: ClosedRange<Double> = 10...20

    /// Resolves the stored values (any of which may be stale or garbage) into a diff theme.
    static func theme(isDark: Bool, lightTheme: String, darkTheme: String, fontID: String, size: Double) -> DiffTheme {
        let name = isDark ? darkTheme : lightTheme
        return DiffTheme(
            highlightrThemeName: name.isEmpty ? (isDark ? defaultDarkTheme : defaultLightTheme) : name,
            fontID: fontID,
            fontSize: clampedSize(size)
        )
    }

    static func clampedSize(_ size: Double) -> CGFloat {
        CGFloat(min(max(size, sizeRange.lowerBound), sizeRange.upperBound))
    }
}

// MARK: - Themes

nonisolated enum CodeThemeCatalog {
    /// Popular themes, in display order. Ids are Highlightr stylesheet names.
    static let curated: [String] = [
        "github", "github-dark", "github-dark-dimmed", "xcode", "xcode-dark",
        "atom-one-light", "onedark", "dracula", "monokai", "nord",
        "tokyo-night-light", "tokyo-night-dark", "night-owl",
        "gruvbox-light", "gruvbox-dark", "solarized-light", "solarized-dark", "vs2015",
    ]

    private static let specialNames: [String: String] = [
        "github": "GitHub", "github-dark": "GitHub Dark", "github-dark-dimmed": "GitHub Dark Dimmed",
        "onedark": "One Dark", "vs2015": "VS 2015", "vs": "Visual Studio", "ir-black": "IR Black",
        "a11y-dark": "A11y Dark", "a11y-light": "A11y Light", "idea": "IDEA", "xt256": "XT256",
    ]

    /// "tokyo-night-dark" -> "Tokyo Night Dark".
    static func prettyName(_ id: String) -> String {
        if let special = specialNames[id] { return special }
        return id
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Curated themes that actually exist (in curated order), then the rest sorted by display name.
    static func organize(available: [String]) -> (popular: [String], more: [String]) {
        let set = Set(available)
        let popular = curated.filter(set.contains)
        let popularSet = Set(popular)
        let more = set.subtracting(popularSet).sorted {
            prettyName($0).localizedCaseInsensitiveCompare(prettyName($1)) == .orderedAscending
        }
        return (popular, more)
    }

    /// Light vs dark tint variants follow the theme's own background, not the system appearance.
    static func isDarkBackground(luminance: Double) -> Bool { luminance < 0.5 }

    /// Relative luminance (Rec. 709 on the sRGB components; good enough to pick a tint).
    static func luminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

// MARK: - Fonts

nonisolated struct CodeFontOption: Equatable, Identifiable {
    /// "system" for SF Mono, otherwise the font family name.
    let id: String
    let name: String
}

nonisolated enum CodeFontCatalog {
    static let systemID = "system"

    /// Listed first, in this order; everything else follows alphabetically.
    static let pinnedFamilies = ["Menlo", "Monaco"]

    /// Old stored ids (before families were stored) -> family name.
    private static let legacyFamilies: [String: String] = [
        "menlo": "Menlo", "monaco": "Monaco", "courier-new": "Courier New",
        "jetbrains-mono": "JetBrains Mono", "fira-code": "Fira Code",
        "cascadia-code": "Cascadia Code", "source-code-pro": "Source Code Pro", "hack": "Hack",
    ]

    /// Installed fixed-pitch families, cached for the process (enumerating fonts is slow).
    static let installed: [CodeFontOption] = {
        let manager = NSFontManager.shared
        return options(families: manager.availableFontFamilies) { family in
            guard let first = manager.availableMembers(ofFontFamily: family)?.first,
                  let postScript = first.first as? String,
                  let font = NSFont(name: postScript, size: 12) else { return false }
            return isFixedWidth(font)
        }
    }()

    /// Nerd Font builds often lack the fixed-pitch flag, so also compare advances of a narrow and a wide glyph.
    static func isFixedWidth(_ font: NSFont) -> Bool {
        if font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace) { return true }
        let narrow = font.advancement(forGlyph: font.glyph(withName: "i")).width
        let wide = font.advancement(forGlyph: font.glyph(withName: "W")).width
        return narrow > 0 && abs(narrow - wide) < 0.01
    }

    static func installedOptions() -> [CodeFontOption] { installed }

    /// Pure: SF Mono, pinned families (when present), then the remaining fixed-pitch families sorted by name.
    static func options(families: [String], isMonospaced: (String) -> Bool) -> [CodeFontOption] {
        let present = Set(families.filter { !$0.hasPrefix(".") && !$0.isEmpty })
        var result = [CodeFontOption(id: systemID, name: "SF Mono")]
        for pinned in pinnedFamilies where present.contains(pinned) {
            result.append(CodeFontOption(id: pinned, name: pinned))
        }
        let skip = Set(pinnedFamilies + ["SF Mono"])
        let rest = present.subtracting(skip)
            .filter(isMonospaced)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        result += rest.map { CodeFontOption(id: $0, name: $0) }
        return result
    }

    /// Maps a stored value (family, legacy id, PostScript name) to a family name, or nil for the system font.
    static func family(forStoredID id: String) -> String? {
        if id == systemID || id.isEmpty { return nil }
        if let legacy = legacyFamilies[id] { return legacy }
        if NSFontManager.shared.availableMembers(ofFontFamily: id) != nil { return id }
        // A PostScript name such as "JetBrainsMono-Regular".
        if let font = NSFont(name: id, size: 12), let family = font.familyName { return family }
        return nil
    }

    struct Member: Equatable {
        let postScriptName: String
        let weight: Int      // NSFontManager scale, 5 = regular
        let isItalic: Bool
    }

    /// Prefers upright Regular, then the upright member closest to Regular, then anything.
    static func preferredMember(_ members: [Member]) -> Member? {
        let upright = members.filter { !$0.isItalic }
        let pool = upright.isEmpty ? members : upright
        return pool.min { abs($0.weight - 5) < abs($1.weight - 5) }
    }

    static func font(id: String, size: CGFloat) -> NSFont {
        let fallback = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        guard let family = family(forStoredID: id),
              let raw = NSFontManager.shared.availableMembers(ofFontFamily: family) else { return fallback }
        let members = raw.compactMap { entry -> Member? in
            guard let ps = entry.first as? String else { return nil }
            let weight = (entry.count > 2 ? entry[2] as? NSNumber : nil)?.intValue ?? 5
            let traits = (entry.count > 3 ? entry[3] as? NSNumber : nil)?.uintValue ?? 0
            return Member(postScriptName: ps, weight: weight,
                          isItalic: NSFontTraitMask(rawValue: traits).contains(.italicFontMask))
        }
        if let member = preferredMember(members), let font = NSFont(name: member.postScriptName, size: size) {
            return font
        }
        return fallback
    }
}

// MARK: - Highlightr stylesheet colors

nonisolated struct CodeThemeColors: Equatable {
    struct RGB: Equatable { var r: Double; var g: Double; var b: Double }
    var background: RGB?
    var text: RGB?

    /// Pulls `background` and `color` from the `.hljs` rule(s) of a minified highlight.js stylesheet.
    static func parse(css: String) -> CodeThemeColors {
        var stripped = css
        while let open = stripped.range(of: "/*"), let close = stripped.range(of: "*/", range: open.upperBound..<stripped.endIndex) {
            stripped.removeSubrange(open.lowerBound..<close.upperBound)
        }

        var result = CodeThemeColors()
        for rule in stripped.split(separator: "}") {
            let parts = rule.split(separator: "{", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let selectors = parts[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard selectors.contains(".hljs") else { continue }
            for declaration in parts[1].split(separator: ";") {
                let pair = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard pair.count == 2 else { continue }
                switch pair[0] {
                case "background", "background-color":
                    if let color = parseColor(pair[1]) { result.background = color }
                case "color":
                    if let color = parseColor(pair[1]) { result.text = color }
                default: break
                }
            }
        }
        return result
    }

    /// Accepts `#rgb`, `#rrggbb`, `#rrggbbaa`, `white` and `black`; a value like `#fff url(...)` uses its first token.
    static func parseColor(_ value: String) -> RGB? {
        let token = value.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        switch token {
        case "white": return RGB(r: 1, g: 1, b: 1)
        case "black": return RGB(r: 0, g: 0, b: 0)
        default: break
        }
        guard token.hasPrefix("#") else { return nil }
        var hex = String(token.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let number = UInt64(hex.prefix(6), radix: 16) else { return nil }
        return RGB(r: Double((number >> 16) & 0xFF) / 255, g: Double((number >> 8) & 0xFF) / 255, b: Double(number & 0xFF) / 255)
    }
}

/// Finds and caches the stylesheet colors of Highlightr themes (Highlightr keeps its own parsed copy private).
nonisolated final class CodeThemeColorStore: @unchecked Sendable {
    static let shared = CodeThemeColorStore()

    private let lock = NSLock()
    private var cache: [String: CodeThemeColors] = [:]

    func colors(for themeName: String) -> CodeThemeColors {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[themeName] { return cached }
        let parsed = Self.css(named: themeName).map(CodeThemeColors.parse(css:)) ?? CodeThemeColors()
        cache[themeName] = parsed
        return parsed
    }

    private static func css(named name: String) -> String? {
        var bundles = Bundle.allBundles + Bundle.allFrameworks + [Bundle.main]
        for bundle in bundles {
            if let nested = bundle.urls(forResourcesWithExtension: "bundle", subdirectory: nil) {
                bundles.append(contentsOf: nested.compactMap(Bundle.init(url:)))
            }
        }
        for bundle in bundles {
            if let path = bundle.path(forResource: name + ".min", ofType: "css"),
               let text = try? String(contentsOfFile: path, encoding: .utf8) {
                return text
            }
        }
        return nil
    }
}
