//
//  GitHubAccountsTests.swift
//  GitHallsTests
//

import Testing
@testable import GitHalls

struct GitHubAccountsTests {
    private let json = """
    {"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"Luckyx128","tokenSource":"keyring"},\
    {"state":"success","active":false,"host":"github.com","login":"lucasAmbiensys","tokenSource":"keyring"}]}}
    """

    private let text = """
    github.com
      ✓ Logged in to github.com account Luckyx128 (keyring)
      - Active account: true
      - Git operations protocol: https
      - Token: gho_************************************

      ✓ Logged in to github.com account lucasAmbiensys (keyring)
      - Active account: false
    """

    @Test func readsLoginsFromJSON() {
        #expect(GitHubAccounts.logins(fromStatusOutput: json) == ["Luckyx128", "lucasAmbiensys"])
    }

    @Test func readsLoginsFromText() {
        #expect(GitHubAccounts.logins(fromStatusOutput: text) == ["Luckyx128", "lucasAmbiensys"])
    }

    @Test func ignoresBrokenLoginsInJSON() {
        let broken = #"{"hosts":{"github.com":[{"state":"error","login":"old"},{"state":"success","login":"ok"}]}}"#
        #expect(GitHubAccounts.logins(fromStatusOutput: broken) == ["ok"])
    }

    @Test func emptyWhenNotLoggedIn() {
        #expect(GitHubAccounts.logins(fromStatusOutput: "You are not logged into any GitHub hosts.").isEmpty)
    }

    @Test func recognisesAccessErrors() {
        #expect(GitHubAccounts.isAccessError("GraphQL: Could not resolve to a Repository with the name 'A/b'. (repository)"))
        #expect(GitHubAccounts.isAccessError("gh: Not Found (HTTP 404)"))
        #expect(GitHubAccounts.isAccessError("Resource not accessible by personal access token"))
    }

    @Test func otherFailuresAreNotAccessErrors() {
        #expect(!GitHubAccounts.isAccessError("a pull request for branch \"x\" already exists"))
        #expect(!GitHubAccounts.isAccessError("could not connect to api.github.com"))
    }

    @Test func triesRememberedAccountFirstThenDefault() {
        let order = GitHubAccounts.attemptOrder(logins: ["a", "b", "c"], remembered: "c")
        #expect(order == ["c", nil, "a", "b"])
    }

    @Test func triesDefaultFirstWithoutMemory() {
        #expect(GitHubAccounts.attemptOrder(logins: ["a", "b"], remembered: nil) == [nil, "a", "b"])
    }
}
