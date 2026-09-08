//
//  JiraQueryTests.swift
//  GitHallsTests
//

import Testing
import Foundation
@testable import GitHalls

struct JiraQueryTests {

    @Test func theBoardOpensOnTheActiveSprint() {
        #expect(JiraQueryPresets.default.id == JiraQueryPresets.activeSprintID)
        #expect(JiraQueryPresets.default.jql.contains("openSprints()"))
        #expect(JiraQueryPresets.default.isBuiltIn)
    }

    @Test func presetIDsAreDistinctAndMarkedBuiltIn() {
        // Hoisted out of #expect: the macro rewrites the expression in a way
        // that loses the rethrows analysis on allSatisfy.
        let distinctIDs = Set(JiraQueryPresets.all.map(\.id)).count
        let allBuiltIn = JiraQueryPresets.all.allSatisfy(\.isBuiltIn)
        let allHaveJQL = JiraQueryPresets.all.allSatisfy { !$0.jql.isEmpty }

        #expect(distinctIDs == JiraQueryPresets.all.count)
        #expect(allBuiltIn)
        #expect(allHaveJQL)
    }

    @Test func combinePutsPresetsFirstAndDropsACustomQueryThatShadowsOne() {
        let mine = JiraQuery(name: "Mine", jql: "project = APP")
        let shadow = JiraQuery(id: JiraQueryPresets.activeSprintID, name: "Shadow", jql: "x")

        let combined = JiraQueryPresets.combine(custom: [shadow, mine])

        #expect(combined.count == JiraQueryPresets.all.count + 1)
        #expect(combined.last?.id == mine.id)
        #expect(combined.first?.name == "Active sprint")
    }

    @Test func aSavedQueryDoesNotCarryTheBuiltInFlag() throws {
        // The flag is code, not settings: a preset decoded from disk would come
        // back as a custom query the user could delete.
        let data = try JSONEncoder().encode(JiraQuery(id: "id", name: "n", jql: "jql", isBuiltIn: true))
        let decoded = try JSONDecoder().decode(JiraQuery.self, from: data)

        #expect(!decoded.isBuiltIn)
        #expect(decoded.name == "n")
    }
}
