//
//  ChatPhotosCardTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import PhotosUI
import Testing
@testable import Flipcash

@MainActor
@Suite("Chat photos card")
struct ChatPhotosCardTests {

    // The picker runs out of process, so a tap can't be driven from here; this pins the behaviour
    // that makes one reach the selection. With `.ordered`, a tapped photo was marked in the picker
    // but the binding never changed, so the Add pill never appeared.
    @Test("The picker reports each tap to the selection as it happens, in order")
    func selectionBehavior_isContinuousAndOrdered() {
        #expect(ChatPhotosCard.selectionBehavior == .continuousAndOrdered)
    }

    @Test("The Add pill counts the selection")
    func addTitle_countsSelection() {
        #expect(ChatPhotosCard.addTitle(count: 1) == "Add 1 photo")
        #expect(ChatPhotosCard.addTitle(count: 3) == "Add 3 photos")
    }
}
