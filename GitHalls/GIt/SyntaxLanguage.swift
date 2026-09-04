//
//  SyntaxLanguage.swift
//  GitHalls
//
//  Maps a file path to a highlight.js language identifier for syntax highlighting.
//

import Foundation

enum SyntaxLanguage {
    /// highlight.js language id for `path`, or `nil` when the extension/name is unknown.
    static func forPath(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent

        if let byName = byBasename[name] ?? byBasename[name.lowercased()] {
            return byName
        }

        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return byExtension[ext]
    }

    private static let byBasename: [String: String] = [
        "Dockerfile": "dockerfile",
        "Makefile": "makefile",
        "GNUmakefile": "makefile",
        "CMakeLists.txt": "cmake",
        "Package.swift": "swift",
        "Podfile": "ruby",
        "Fastfile": "ruby",
        "Gemfile": "ruby",
        "Rakefile": "ruby",
        ".gitconfig": "ini",
    ]

    private static let byExtension: [String: String] = [
        "swift": "swift",
        "m": "objectivec",
        "mm": "objectivec",
        "h": "objectivec",
        "hpp": "cpp",
        "hh": "cpp",
        "c": "c",
        "cc": "cpp",
        "cpp": "cpp",
        "cxx": "cpp",
        "js": "javascript",
        "jsx": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "ts": "typescript",
        "tsx": "typescript",
        "py": "python",
        "pyi": "python",
        "rb": "ruby",
        "go": "go",
        "rs": "rust",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "cs": "csharp",
        "php": "php",
        "pl": "perl",
        "pm": "perl",
        "lua": "lua",
        "r": "r",
        "scala": "scala",
        "clj": "clojure",
        "ex": "elixir",
        "exs": "elixir",
        "erl": "erlang",
        "hs": "haskell",
        "dart": "dart",
        "groovy": "groovy",
        "gradle": "groovy",
        "json": "json",
        "json5": "json",
        "yaml": "yaml",
        "yml": "yaml",
        "toml": "ini",
        "ini": "ini",
        "cfg": "ini",
        "conf": "ini",
        "xml": "xml",
        "plist": "xml",
        "html": "xml",
        "htm": "xml",
        "xhtml": "xml",
        "svg": "xml",
        "vue": "xml",
        "css": "css",
        "scss": "scss",
        "sass": "scss",
        "less": "less",
        "md": "markdown",
        "markdown": "markdown",
        "sh": "bash",
        "bash": "bash",
        "zsh": "bash",
        "fish": "bash",
        "sql": "sql",
        "graphql": "graphql",
        "gql": "graphql",
        "proto": "protobuf",
        "dockerfile": "dockerfile",
        "cmake": "cmake",
        "make": "makefile",
        "mk": "makefile",
        "diff": "diff",
        "patch": "diff",
    ]
}
