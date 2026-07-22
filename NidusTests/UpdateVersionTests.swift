//
//  UpdateVersionTests.swift
//  NidusTests
//
//  Version comparison is the whole correctness of the update notice: get it wrong and Nidus either
//  nags about a release you already have, or stays quiet about one you don't.
//

import Testing
@testable import Nidus

struct UpdateVersionTests {

    @Test func newerVersionsAreDetected() {
        #expect(UpdateChecker.isNewer("1.1", than: "1.0"))
        #expect(UpdateChecker.isNewer("2.0", than: "1.9"))
        #expect(UpdateChecker.isNewer("1.0.1", than: "1.0"))
    }

    @Test func sameOrOlderIsNotNewer() {
        #expect(!UpdateChecker.isNewer("1.0", than: "1.0"))
        #expect(!UpdateChecker.isNewer("1.0", than: "1.1"))
        #expect(!UpdateChecker.isNewer("1.9", than: "2.0"))
    }

    /// The one a string compare gets backwards — "1.10" sorts before "1.9" alphabetically.
    @Test func doubleDigitComponentsCompareNumerically() {
        #expect(UpdateChecker.isNewer("1.10", than: "1.9"))
        #expect(!UpdateChecker.isNewer("1.9", than: "1.10"))
        #expect(UpdateChecker.isNewer("1.0.10", than: "1.0.9"))
    }

    /// Trailing zeros are not a new release: shipping "1.1.0" must not nag someone on "1.1".
    @Test func missingComponentsCountAsZero() {
        #expect(!UpdateChecker.isNewer("1.1.0", than: "1.1"))
        #expect(!UpdateChecker.isNewer("1.1", than: "1.1.0"))
        #expect(UpdateChecker.isNewer("1.1.1", than: "1.1"))
    }
}
