//
//  ChatViewController+TestSupport.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import FlipcashCore
@testable import FlipcashUI

extension ChatViewController {

    /// A controller with its view loaded and `items` applied — the arrange step shared by the
    /// chat suites. Off-window, both animated and non-animated updates render synchronously.
    static func loaded(items: [ChatItem], animated: Bool = true) -> ChatViewController {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        controller.update(items: items, animated: animated)
        return controller
    }

    /// Hosts a fresh controller in a key window sized like an iPhone, so updates run the
    /// on-screen (animated batch) path. The window is returned because the caller must keep it
    /// alive for the test's duration — dropping it detaches the view mid-test.
    static func windowed() -> (controller: ChatViewController, window: UIWindow) {
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return (controller, window)
    }

    /// Lets layout, self-sizing, and in-flight batch updates settle across main-runloop turns.
    /// UIKit exposes no awaitable hook for collection-view batch-update completion, so this
    /// drains the run loop in short turns — tune the timing here, never per test.
    func settle(turns: Int = 3) async {
        for _ in 0..<turns {
            view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    /// Settles until `condition` holds (re-checked between run-loop turns), up to `timeout`.
    /// For waits on spring/batch settle, whose duration shifts under load (CI, TSan) — a fixed
    /// turn count either flakes or overwaits.
    func settle(until condition: () -> Bool, timeout: TimeInterval = 5) async {
        let start = ContinuousClock.now
        while !condition(), ContinuousClock.now - start < .seconds(timeout) {
            view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
}
