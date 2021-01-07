//
//  AppVersionTests.swift
//  StoreVersionTests
//
//  Created by Visarut Tippun on 22/11/2026.
//  Copyright © 2026 Visarut Tippun. All rights reserved.
//

import StoreVersion
import Testing

@Suite("AppVersion")
struct AppVersionTests {
    @Test(arguments: [("1.2.3", [1, 2, 3]),
                      ("10", [10]),
                      ("  2.0 ", [2, 0]),
                      ("v3.4", [3, 4]),
                      ("V3.4", [3, 4]),
                      ("1.2.3 (45)", [1, 2, 3]),
                      ("1.2.3-beta", [1, 2, 3]),
                      ("1.2.", [1, 2]),
                      ("1..2", [1]),
                      ("01.002", [1, 2])])
    func parsesNumericComponents(input: String, expected: [Int]) {
        #expect(AppVersion(input)?.components == expected)
    }

    @Test(arguments: ["", "   ", "beta", ".1", "v", "-1.0", "99999999999999999999.0", "١.٢"])
    func rejectsInvalidStrings(input: String) {
        #expect(AppVersion(input) == nil)
    }

    @Test func rejectsInvalidComponents() {
        #expect(AppVersion(components: []) == nil)
        #expect(AppVersion(components: [1, -1]) == nil)
        #expect(AppVersion(components: [0])?.description == "0")
    }

    @Test func descriptionIsNormalizedNumbers() throws {
        #expect(try #require(AppVersion("v01.2.3 (4)")).description == "1.2.3")
    }

    @Test(arguments: [("1.0", "1.0.0"),
                      ("1", "1.0.0.0"),
                      ("2.10", "2.10.0"),
                      ("0", "0.0")])
    func equivalentVersionsAreEqual(lhs: String, rhs: String) throws {
        let a = try #require(AppVersion(lhs))
        let b = try #require(AppVersion(rhs))
        #expect(a == b)
        #expect(!(a < b))
        #expect(!(b < a))
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b]).count == 1)
    }

    @Test(arguments: [("1.0", "1.0.1"),
                      ("1.9", "1.10"),
                      ("1.2.3", "1.3"),
                      ("1", "1.0.0.1"),
                      ("2.0.9", "10.0"),
                      ("0.9.9", "1")])
    func ordersNumerically(older: String, newer: String) throws {
        let a = try #require(AppVersion(older))
        let b = try #require(AppVersion(newer))
        #expect(a < b)
        #expect(b > a)
        #expect(a != b)
    }
}
