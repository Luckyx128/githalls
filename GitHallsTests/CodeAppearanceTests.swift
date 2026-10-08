//
//  CodeAppearanceTests.swift
//  GitHallsTests
//

import AppKit
import Testing
@testable import GitHalls

struct CodeAppearanceTests {
    @Test(arguments: [
        ("tokyo-night-dark", "Tokyo Night Dark"),
        ("github-dark-dimmed", "GitHub Dark Dimmed"),
        ("onedark", "One Dark"),
        ("vs2015", "VS 2015"),
        ("atom-one-light", "Atom One Light"),
        ("nord", "Nord"),
    ])
    func prettifiesThemeNames(id: String, expected: String) {
        #expect(CodeThemeCatalog.prettyName(id) == expected)
    }

    @Test func organizesCuratedFirstAndSkipsMissing() {
        let result = CodeThemeCatalog.organize(available: ["zenburn", "nord", "github", "agate"])
        #expect(result.popular == ["github", "nord"])
        #expect(result.more == ["agate", "zenburn"])
    }

    @Test func picksTintVariantByBackgroundLuminance() {
        #expect(CodeThemeCatalog.isDarkBackground(luminance: CodeThemeCatalog.luminance(red: 0.1, green: 0.1, blue: 0.12)))
        #expect(!CodeThemeCatalog.isDarkBackground(luminance: CodeThemeCatalog.luminance(red: 1, green: 1, blue: 1)))
    }

    @Test func listsMonospacedFamiliesPinnedFirstThenAlphabetical() {
        let families = ["Zapfino", "JetBrainsMono Nerd Font", ".Hidden Mono", "Monaco", "Courier New",
                        "Helvetica", "Menlo", "Fira Code", "SF Mono"]
        let mono: Set = ["JetBrainsMono Nerd Font", "Monaco", "Courier New", "Menlo", "Fira Code", ".Hidden Mono"]
        let result = CodeFontCatalog.options(families: families) { mono.contains($0) }
        #expect(result.map(\.id) == ["system", "Menlo", "Monaco", "Courier New", "Fira Code", "JetBrainsMono Nerd Font"])
        #expect(result.first?.name == "SF Mono")
    }

    @Test func prefersRegularThenClosestUprightMember() {
        typealias M = CodeFontCatalog.Member
        let bold = M(postScriptName: "X-Bold", weight: 9, isItalic: false)
        let regular = M(postScriptName: "X-Regular", weight: 5, isItalic: false)
        let italic = M(postScriptName: "X-Italic", weight: 5, isItalic: true)
        #expect(CodeFontCatalog.preferredMember([bold, italic, regular]) == regular)
        #expect(CodeFontCatalog.preferredMember([bold]) == bold)
        #expect(CodeFontCatalog.preferredMember([bold, italic]) == bold)
        #expect(CodeFontCatalog.preferredMember([]) == nil)
    }

    @Test func legacyAndUnknownFontIDsStillResolve() {
        #expect(CodeFontCatalog.family(forStoredID: "system") == nil)
        #expect(CodeFontCatalog.family(forStoredID: "menlo") == "Menlo")
        #expect(CodeFontCatalog.family(forStoredID: "Menlo-Regular") == "Menlo")
        #expect(CodeFontCatalog.font(id: "no-such-font", size: 13).pointSize == 13)
        #expect(CodeFontCatalog.font(id: "Menlo", size: 13).familyName == "Menlo")
    }

    @Test func parsesHljsColorsFromCSS() {
        let css = "/* c */.hljs{display:block;background:#1f2024;color:white}.hljs-keyword{color:#f00}"
        let colors = CodeThemeColors.parse(css: css)
        #expect(colors.text == .init(r: 1, g: 1, b: 1))
        #expect(colors.background?.r == Double(0x1f) / 255)
        #expect(CodeThemeColors.parseColor("#fff")?.g == 1)
    }

    @Test func readsBundledThemeAndDerivesDarkness() {
        #expect(DiffTextTheme.make(.dark).isDark)
        #expect(!DiffTextTheme.make(.light).isDark)
        let github = DiffTextTheme.make(DiffTheme(highlightrThemeName: "github-dark", fontID: "system", fontSize: 14))
        #expect(github.isDark)
        #expect(github.font.pointSize == 14)
        #expect(github.headerFont.pointSize == 13)
    }

    @Test func cacheKeyIncludesFontAndSize() {
        let a = DiffTheme(highlightrThemeName: "nord", fontID: "system", fontSize: 12)
        let b = DiffTheme(highlightrThemeName: "nord", fontID: "menlo", fontSize: 12)
        let c = DiffTheme(highlightrThemeName: "nord", fontID: "system", fontSize: 13)
        #expect(Set([a.cacheKey, b.cacheKey, c.cacheKey]).count == 3)
    }

    @Test func clampsSize() {
        #expect(CodeAppearance.clampedSize(4) == 10)
        #expect(CodeAppearance.clampedSize(99) == 20)
    }
}
