//
//  QuickActionsControllerTests.swift
//  FlipcashTests
//

import Testing
import UIKit
@testable import Flipcash

@Suite("QuickActionsController")
struct QuickActionsControllerTests {

    @Test("With Send enabled, actions follow tab-bar order: discover, cash, send, wallet")
    func orderWithSend() {
        let types = QuickActionsController.shortcutItems(includeSend: true).map(\.type)
        #expect(types == [
            "com.flipcash.shortcut.discover",
            "com.flipcash.shortcut.give",
            "com.flipcash.shortcut.send",
            "com.flipcash.shortcut.wallet",
        ])
    }

    @Test("With Send disabled, the order is discover, cash, wallet")
    func orderWithoutSend() {
        let types = QuickActionsController.shortcutItems(includeSend: false).map(\.type)
        #expect(types == [
            "com.flipcash.shortcut.discover",
            "com.flipcash.shortcut.give",
            "com.flipcash.shortcut.wallet",
        ])
    }

    @Test("Send action carries the flipcash://send deep link")
    func sendActionContents() throws {
        let send = try #require(
            QuickActionsController.shortcutItems(includeSend: true)
                .first { $0.type == "com.flipcash.shortcut.send" }
        )
        #expect(send.localizedTitle == "Send")
        #expect(send.userInfo?["url"] as? String == "flipcash://send")
    }
}
