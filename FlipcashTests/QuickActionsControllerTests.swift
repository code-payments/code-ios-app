//
//  QuickActionsControllerTests.swift
//  FlipcashTests
//

import Testing
import UIKit
@testable import Flipcash

@Suite("QuickActionsController")
struct QuickActionsControllerTests {

    @Test("Actions follow tab-bar order: discover, cash, wallet")
    func order() {
        let types = QuickActionsController.shortcutItems().map(\.type)
        #expect(types == [
            "com.flipcash.shortcut.discover",
            "com.flipcash.shortcut.give",
            "com.flipcash.shortcut.wallet",
        ])
    }
}
