//
//  UnreadCountLabelTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import FlipcashCore

@Suite("Unread count label")
struct UnreadCountLabelTests {

    @Test("counts up to 99 show as numbers and anything above reads 99+", arguments: [
        (1, "1"),
        (99, "99"),
        (100, "99+"),
        (150, "99+"),
    ])
    func text_capsAt99(_ count: Int, _ expected: String) {
        #expect(UnreadCountLabel.text(for: count) == expected)
    }
}
