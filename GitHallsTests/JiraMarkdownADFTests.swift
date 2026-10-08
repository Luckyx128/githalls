//
//  JiraMarkdownADFTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraMarkdownADFTests {
    private func blocks(_ markdown: String) -> [[String: Any]] {
        JiraMarkdownADF.document(from: markdown)["content"] as! [[String: Any]]
    }

    private func types(_ markdown: String) -> [String] {
        blocks(markdown).compactMap { $0["type"] as? String }
    }

    @Test func documentEnvelope() {
        let doc = JiraMarkdownADF.document(from: "hi")
        #expect(doc["type"] as? String == "doc")
        #expect(doc["version"] as? Int == 1)
    }

    @Test func blockKinds() {
        let markdown = "# Title\n\nSome text\n\n- a\n- b\n\n1. one\n2. two\n\n> quote\n\n```swift\nlet x = 1\n```"
        #expect(types(markdown) == ["heading", "paragraph", "bulletList", "orderedList", "blockquote", "codeBlock"])
    }

    @Test func headingLevel() {
        let heading = blocks("## Two")[0]
        #expect((heading["attrs"] as? [String: Any])?["level"] as? Int == 2)
    }

    @Test func inlineMarks() {
        let paragraph = blocks("a **bold** and *it* and `code` and [l](http://x)")[0]
        let nodes = paragraph["content"] as! [[String: Any]]
        let marks = nodes.compactMap { ($0["marks"] as? [[String: Any]])?.first?["type"] as? String }
        #expect(marks == ["strong", "em", "code", "link"])
    }

    @Test func roundTripsThroughPlainText() {
        let doc = JiraMarkdownADF.document(from: "First\n\n- one\n- two")
        let text = JiraADF.plainText(from: doc)
        #expect(text.contains("First"))
        #expect(text.contains("one") && text.contains("two"))
    }

    @Test func emptyInputHasNoBlocks() {
        #expect(blocks("  \n\n").isEmpty)
    }
}
