//
//  ChatScreenKeyboardFloorTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
@testable import FlipcashUI

/// Where the bar rests relative to a keyboard, driven by `keyboardWillChangeFrame` notifications.
///
/// The notifications are posted by hand with a zero duration, so the bar's destination can be read
/// off its frame in the same pass. A share sheet's Messages composer is another process, and its
/// keyboard posts the same notification with `keyboardIsLocalUserInfoKey` false.
@MainActor
@Suite("Chat screen keyboard floor")
struct ChatScreenKeyboardFloorTests {

    private let windowFrame = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let keyboardHeight: CGFloat = 336

    /// A screen on a live window, since the floor ignores keyboards while its view is off-window.
    private func makeScreen() -> (ChatScreenViewController, UIView, UIWindow) {
        let bar = UIView()
        let screen = ChatScreenViewController(bar: bar)
        let window = UIWindow(frame: windowFrame)
        window.rootViewController = screen
        window.makeKeyAndVisible()
        screen.loadViewIfNeeded()
        UIView.performWithoutAnimation {
            screen.setBarHeight(60, replying: false)
        }
        window.layoutIfNeeded()
        return (screen, bar, window)
    }

    /// How far the bar's bottom edge sits above the bottom of the screen.
    private func barLift(_ bar: UIView, _ screen: ChatScreenViewController, _ window: UIWindow) -> CGFloat {
        window.layoutIfNeeded()
        guard let clip = bar.superview else { return 0 }
        return screen.view.bounds.maxY - clip.frame.maxY
    }

    private func postKeyboard(endFrame: CGRect, isLocal: Bool) {
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: endFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.0,
                UIResponder.keyboardIsLocalUserInfoKey: isLocal,
            ]
        )
    }

    private var raisedKeyboard: CGRect {
        CGRect(x: 0, y: windowFrame.maxY - keyboardHeight, width: windowFrame.width, height: keyboardHeight)
    }

    @Test("The composer's own keyboard lifts the bar onto its top edge")
    func localKeyboard_liftsTheBar() {
        let (screen, bar, window) = makeScreen()
        let resting = barLift(bar, screen, window)

        postKeyboard(endFrame: raisedKeyboard, isLocal: true)
        #expect(barLift(bar, screen, window) == keyboardHeight)

        postKeyboard(endFrame: raisedKeyboard.offsetBy(dx: 0, dy: keyboardHeight), isLocal: true)
        #expect(barLift(bar, screen, window) == resting)
    }

    @Test("Another process's keyboard leaves the bar where it rests")
    func remoteKeyboard_leavesTheBarResting() {
        let (screen, bar, window) = makeScreen()
        let resting = barLift(bar, screen, window)

        postKeyboard(endFrame: raisedKeyboard, isLocal: false)
        #expect(barLift(bar, screen, window) == resting)
    }

    @Test("A remote keyboard lowered with no usable frame does not strand the bar")
    func remoteKeyboardLoweredWithEmptyFrame_leavesTheBarResting() {
        let (screen, bar, window) = makeScreen()
        let resting = barLift(bar, screen, window)

        // The Messages composer's keyboard goes up while the recipient is typed, and its lowering
        // arrives with an empty frame, which the floor skips.
        postKeyboard(endFrame: raisedKeyboard, isLocal: false)
        postKeyboard(endFrame: .zero, isLocal: false)
        #expect(barLift(bar, screen, window) == resting)
    }
}
