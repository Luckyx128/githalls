//
//  AutoFetchTests.swift
//  GitHallsTests
//

import Foundation
import Testing
@testable import GitHalls

struct AutoFetchTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func neverFetchedIsDue() {
        #expect(AutoFetch.isDue(lastFetch: nil, now: now, minimumAge: 60))
    }

    @Test func recentFetchIsNotDue() {
        #expect(!AutoFetch.isDue(lastFetch: now.addingTimeInterval(-30), now: now, minimumAge: 60))
    }

    @Test func oldFetchIsDue() {
        #expect(AutoFetch.isDue(lastFetch: now.addingTimeInterval(-61), now: now, minimumAge: 60))
    }

    @Test(arguments: [
        (10.0, "Fetched just now"),
        (300.0, "Fetched 5 min ago"),
        (7200.0, "Fetched 2 h ago"),
        (172_800.0, "Fetched 2 d ago")
    ])
    func ageLabel(age: Double, expected: String) {
        #expect(AutoFetch.ageLabel(lastFetch: now.addingTimeInterval(-age), now: now) == expected)
    }

    @Test func ageLabelWithoutFetch() {
        #expect(AutoFetch.ageLabel(lastFetch: nil, now: now) == "Not fetched yet")
    }
}
