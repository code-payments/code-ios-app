//
//  AttachMenuTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Attach menu")
struct AttachMenuTests {

    @Test("A chat that takes cash and media lists Cash, Camera, Photos, top to bottom")
    func allRowsInOrder() {
        let items = AttachMenuItem.items(showsCash: true, acceptsMedia: true, attachedCount: 0)
        #expect(items == [.cash, .camera, .photos])
    }

    @Test("An E2EE chat keeps Cash and drops Camera and Photos")
    func mediaRowsHiddenWithoutMedia() {
        let items = AttachMenuItem.items(showsCash: true, acceptsMedia: false, attachedCount: 0)
        #expect(items == [.cash])
    }

    @Test("A chat with no Send Cash target lists only the media rows")
    func cashRowHiddenWithoutCash() {
        let items = AttachMenuItem.items(showsCash: false, acceptsMedia: true, attachedCount: 0)
        #expect(items == [.camera, .photos])
    }

    @Test("A chat that takes neither cash nor media has no rows")
    func noRows() {
        let items = AttachMenuItem.items(showsCash: false, acceptsMedia: false, attachedCount: 0)
        #expect(items.isEmpty)
    }

    @Test("Camera and Photos stay until the composer is full", arguments: [1, 5, 9])
    func mediaRowsBelowLimit(attachedCount: Int) {
        let items = AttachMenuItem.items(showsCash: true, acceptsMedia: true, attachedCount: attachedCount)
        #expect(items == [.cash, .camera, .photos])
    }

    @Test("Camera and Photos leave once the composer holds the maximum")
    func mediaRowsHiddenAtLimit() {
        let items = AttachMenuItem.items(
            showsCash: true,
            acceptsMedia: true,
            attachedCount: ComposerModel.maxAttachments
        )
        #expect(items == [.cash])
    }

    @Test("The picker may add only what is left of the maximum", arguments: [
        (0, 10),
        (3, 7),
        (9, 1),
        (10, 0),
    ])
    func selectionLimit(attachedCount: Int, expected: Int) {
        #expect(AttachMenuItem.photosSelectionLimit(attachedCount: attachedCount) == expected)
    }
}
