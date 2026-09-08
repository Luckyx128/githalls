//
//  JiraADFTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraADFTests {
    private func text(_ json: String) -> String {
        JiraADF.plainText(from: try! JSONSerialization.jsonObject(with: Data(json.utf8)))
    }

    @Test func paragraphsBecomeLines() {
        let result = text("""
        {"type":"doc","version":1,"content":[
          {"type":"paragraph","content":[{"type":"text","text":"Hello "},{"type":"text","text":"world","marks":[{"type":"strong"}]}]},
          {"type":"paragraph","content":[{"type":"text","text":"Second"}]}
        ]}
        """)

        #expect(result == "Hello world\nSecond")
    }

    @Test func listsGetMarkersAndNestedListsIndent() {
        let result = text("""
        {"type":"doc","content":[
          {"type":"orderedList","content":[
            {"type":"listItem","content":[
              {"type":"paragraph","content":[{"type":"text","text":"first"}]},
              {"type":"bulletList","content":[
                {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"inner"}]}]}
              ]}
            ]},
            {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"second"}]}]}
          ]}
        ]}
        """)

        #expect(result == "1. first\n  • inner\n2. second")
    }

    @Test func hardBreaksMentionsAndLinksReadInline() {
        let result = text("""
        {"type":"doc","content":[
          {"type":"paragraph","content":[
            {"type":"text","text":"Ask "},
            {"type":"mention","attrs":{"id":"1","text":"@Ana"}},
            {"type":"hardBreak"},
            {"type":"inlineCard","attrs":{"url":"https://acme.atlassian.net/browse/APP-1"}},
            {"type":"text","text":" "},
            {"type":"emoji","attrs":{"shortName":":+1:","text":"👍"}}
          ]}
        ]}
        """)

        #expect(result == "Ask @Ana\nhttps://acme.atlassian.net/browse/APP-1 👍")
    }

    @Test func quotesAndCodeKeepTheirShape() {
        let result = text("""
        {"type":"doc","content":[
          {"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"quoted"}]}]},
          {"type":"codeBlock","attrs":{"language":"bash"},"content":[{"type":"text","text":"git status\\ngit log"}]},
          {"type":"rule"},
          {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Title"}]}
        ]}
        """)

        #expect(result == "> quoted\ngit status\ngit log\n———\nTitle")
    }

    @Test func tablesReadRowByRow() {
        let result = text("""
        {"type":"doc","content":[
          {"type":"table","content":[
            {"type":"tableRow","content":[
              {"type":"tableHeader","content":[{"type":"paragraph","content":[{"type":"text","text":"A"}]}]},
              {"type":"tableHeader","content":[{"type":"paragraph","content":[{"type":"text","text":"B"}]}]}
            ]},
            {"type":"tableRow","content":[
              {"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"1"}]}]},
              {"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"2"}]}]}
            ]}
          ]}
        ]}
        """)

        #expect(result == "A | B\n1 | 2")
    }

    @Test func blankRunsCollapseAndUnknownNodesStillRead() {
        let result = text("""
        {"type":"doc","content":[
          {"type":"paragraph","content":[]},
          {"type":"paragraph","content":[]},
          {"type":"somethingNew","content":[{"type":"paragraph","content":[{"type":"text","text":"still here"}]}]},
          {"type":"paragraph","content":[]},
          {"type":"paragraph","content":[]},
          {"type":"paragraph","content":[{"type":"text","text":"end"}]}
        ]}
        """)

        #expect(result == "still here\n\nend")
    }

    @Test func nothingInNothingOut() {
        #expect(JiraADF.plainText(from: nil) == "")
        #expect(JiraADF.plainText(from: NSNull()) == "")
        #expect(text("{\"type\":\"doc\",\"content\":[]}") == "")
    }
}
