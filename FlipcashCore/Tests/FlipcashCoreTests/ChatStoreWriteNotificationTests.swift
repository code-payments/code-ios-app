//
//  ChatStoreWriteNotificationTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Synchronization
import Testing
@testable import FlipcashCore

@Suite("ChatStoreWriteNotification", .serialized)
struct ChatStoreWriteNotificationTests {

    /// Counts handler calls from whichever thread the notification center delivers on.
    private final class Counter: Sendable {
        private let count = Mutex(0)
        var value: Int { count.withLock { $0 } }
        func increment() { count.withLock { $0 += 1 } }
    }

    @Test("a post reaches a live observer")
    func postReachesObserver() async throws {
        let counter = Counter()
        let token = ChatStoreWriteNotification.observe { counter.increment() }

        ChatStoreWriteNotification.post()

        for _ in 0..<100 where counter.value == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(counter.value > 0)
        ChatStoreWriteNotification.stopObserving(token)
    }

    @Test("a released token stops observing without stopObserving")
    func releasedTokenStopsObserving() async throws {
        let counter = Counter()
        var token: AnyObject? = ChatStoreWriteNotification.observe { counter.increment() }
        _ = token
        token = nil

        ChatStoreWriteNotification.post()

        // The positive test above shows delivery lands well inside this window.
        try await Task.sleep(for: .milliseconds(500))
        #expect(counter.value == 0)
    }
}
