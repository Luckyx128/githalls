//
//  FilePreviewTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct FilePreviewTests {
    @Test(arguments: [
        "assets/logo.png", "photo.JPG", "a/b/c.jpeg", "icon.gif",
        "shot.webp", "old.bmp", "IMG_0042.HEIC", "scan.tiff", "favicon.ico"
    ])
    func readsAnImageByItsExtension(path: String) {
        #expect(FilePreview.kind(for: path) == .image)
    }

    @Test(arguments: [
        "report.pdf", "archive.zip", "Font.ttf", "notes.docx",
        "Makefile", "bin/tool", "data.sqlite"
    ])
    func treatsEverythingElseAsSomethingToDescribe(path: String) {
        #expect(FilePreview.kind(for: path) == .other)
    }

    @Test func doesNotMistakeANameForAnExtension() {
        // The extension is the last component, not any substring of the path.
        #expect(FilePreview.kind(for: "png/notes.txt") == .other)
        #expect(FilePreview.kind(for: "my.png.bak") == .other)
    }

    @Test func formatsASizeAPersonCanRead() {
        #expect(FilePreview.formattedSize(1_500_000).contains("MB"))
        // ByteCountFormatter spells this "Zero KB", not "0" — still a size.
        #expect(!FilePreview.formattedSize(0).isEmpty)
    }
}
