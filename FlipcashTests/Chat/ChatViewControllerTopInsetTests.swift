//
//  ChatViewControllerTopInsetTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatViewController top inset")
struct ChatViewControllerTopInsetTests {

    /// A controller in a window showing `message`, with its row lifted as a long press lifts it.
    private func liftedController(_ message: ChatMessage) async -> (ChatViewController, UIWindow) {
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.update(items: [.message(message)], animated: false)
        for _ in 0..<3 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
        #expect(controller.beginLift(for: message, in: controller.view) != nil)
        return (controller, window)
    }

    @Test("A top inset set while the menu is up survives the menu closing")
    func topInsetSetUnderMenu_survivesEndLift() async {
        let message = ChatMessage(id: "a", text: "Pin me", sender: .me, actions: [.pin])
        let (controller, window) = await liftedController(message)

        // Pin from the menu raises the pin bar while the lift is still up.
        controller.setTopInset(63)
        controller.endLift()

        #expect(controller.collectionView.contentInset.top == 63)
        _ = window
    }
}
