//
//  UnreadBadgeTextTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import FlipcashCore

@Suite("Unread badge text")
struct UnreadBadgeTextTests {

    @Test("counts render as numbers up to the cap, then 99+", arguments: [
        (150, "99+"), (100, "99+"), (99, "99"), (1, "1"),
    ])
    func text_capsAtNinetyNine(_ count: Int, _ expected: String) {
        #expect(UnreadBadgeText.text(for: count) == expected)
    }

    @Test("zero hides the badge")
    func text_zeroIsHidden() {
        #expect(UnreadBadgeText.text(for: 0) == nil)
    }
}
