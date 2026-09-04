//
//  SyntaxLanguageTests.swift
//  GitHallsTests
//

import Foundation
import Testing
@testable import GitHalls

struct SyntaxLanguageTests {

    @Test func mapsCommonExtensions() {
        #expect(SyntaxLanguage.forPath("Sources/App/Main.swift") == "swift")
        #expect(SyntaxLanguage.forPath("web/app.ts") == "typescript")
        #expect(SyntaxLanguage.forPath("web/app.tsx") == "typescript")
        #expect(SyntaxLanguage.forPath("script.py") == "python")
        #expect(SyntaxLanguage.forPath("main.go") == "go")
        #expect(SyntaxLanguage.forPath("lib.rs") == "rust")
        #expect(SyntaxLanguage.forPath("data.json") == "json")
        #expect(SyntaxLanguage.forPath("config.yml") == "yaml")
        #expect(SyntaxLanguage.forPath("Header.h") == "objectivec")
    }

    @Test func isCaseInsensitiveOnExtension() {
        #expect(SyntaxLanguage.forPath("A/B/File.SWIFT") == "swift")
    }

    @Test func handlesSpecialBasenames() {
        #expect(SyntaxLanguage.forPath("docker/Dockerfile") == "dockerfile")
        #expect(SyntaxLanguage.forPath("Makefile") == "makefile")
        #expect(SyntaxLanguage.forPath("ios/Podfile") == "ruby")
    }

    @Test func unknownOrExtensionlessIsNil() {
        #expect(SyntaxLanguage.forPath("LICENSE") == nil)
        #expect(SyntaxLanguage.forPath("bin/tool") == nil)
        #expect(SyntaxLanguage.forPath("weird.zzz") == nil)
        #expect(SyntaxLanguage.forPath("") == nil)
    }
}
