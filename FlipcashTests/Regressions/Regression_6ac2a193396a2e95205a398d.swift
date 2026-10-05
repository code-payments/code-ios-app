//
//  Regression_6ac2a193396a2e95205a398d.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// 2026.9.4 crashed when a chat screen left the window while a bubble's menu was up: closing the
/// menu built a `UITargetedPreview` from a bubble with no window, and UIKit asserted. The lift
/// that replaced that menu has to land and hand the transcript back whenever the screen goes, so
/// nothing is left reaching for a bubble that is no longer on screen.
@MainActor
@Suite("Regression: 6ac2a19 – Lift outlives a chat screen that leaves the window", .bug("6ac2a193396a2e95205a398d"))
struct Regression_6ac2a19 {

    private let message = ChatMessage(id: "a", text: "https://flipcash.com", sender: .other, actions: [.copy])

    /// A chat screen in a navigation stack on a rendering window, with `message`'s bubble lifted by
    /// a long press. Attached to the host's scene because the lift's overlay presents in a window
    /// on the screen's scene.
    private func liftedScreen() async throws -> (UINavigationController, ChatViewController, UIWindow) {
        let screen = ChatScreenViewController(bar: UIView())
        let navigation = UINavigationController(rootViewController: screen)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        screen.loadViewIfNeeded()
        screen.update(items: [.message(message)])
        let transcript = try #require(screen.children.compactMap { $0 as? ChatViewController }.first)
        // A few rendered frames, so the bubble has a cell and a frame for the lift to snapshot.
        for _ in 0..<3 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }

        transcript.onBubbleLongPress?(message, .zero)
        // Guards against a false green: unless the lift is really up, nothing below is tested.
        try #require(transcript.liftLanding() != nil)
        return (navigation, transcript, window)
    }

    private func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Queues work behind the lift and waits for it to run. It runs only once the lift has landed
    /// and released the transcript.
    private func expectLiftReleased(_ transcript: ChatViewController, released: () -> Void) async throws {
        var ran = false
        transcript.afterContextMenu { ran = true }
        released()
        try await waitUntil { ran }
        #expect(transcript.liftLanding() == nil)
    }

    @Test("Pushing a screen over the chat lands the lift and releases the transcript")
    func push_releasesLift() async throws {
        let (navigation, transcript, window) = try await liftedScreen()
        defer { close(window) }

        try await expectLiftReleased(transcript) {
            navigation.pushViewController(UIViewController(), animated: false)
        }
    }

    @Test("Covering the chat full screen lands the lift and releases the transcript")
    func fullScreenCover_releasesLift() async throws {
        let (navigation, transcript, window) = try await liftedScreen()
        defer { close(window) }

        try await expectLiftReleased(transcript) {
            let cover = UIViewController()
            cover.modalPresentationStyle = .fullScreen
            navigation.present(cover, animated: false)
        }
    }
}
