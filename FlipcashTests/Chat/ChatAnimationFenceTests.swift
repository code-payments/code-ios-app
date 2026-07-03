//
//  ChatAnimationFenceTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import FlipcashUI

/// The fence is the transcript's crash guard: ChatLayout's `restoreContentOffset` answers
/// attribute queries with nil while it re-anchors, so inset writes, offset restores, and
/// transcript pushes must never overlap an animated transaction — UIKit throws
/// `NSInternalInconsistencyException: missing final attributes for cell` when they collide.
/// These tests pin the serialization contract every chat-transcript mutation relies on.
@MainActor
@Suite("Chat animation fence")
struct ChatAnimationFenceTests {

    @Test("Work runs immediately while idle")
    func idle_runsImmediately() {
        let fence = ChatAnimationFence()
        var ran = false
        fence.whenIdle { ran = true }
        #expect(ran)
    }

    @Test("Work defers while any transaction is active and replays when the last settles")
    func active_defersUntilLastEnd() {
        let fence = ChatAnimationFence()
        fence.begin()
        fence.begin()
        var ran = false
        fence.whenIdle { ran = true }
        fence.end()
        #expect(!ran, "one transaction is still in flight")
        fence.end()
        #expect(ran)
    }

    @Test("Deferred work replays in registration order")
    func drain_replaysInOrder() {
        let fence = ChatAnimationFence()
        fence.begin()
        var order: [Int] = []
        fence.whenIdle { order.append(1) }
        fence.whenIdle { order.append(2) }
        fence.end()
        #expect(order == [1, 2])
    }

    @Test("A replay that begins a new transaction re-defers the work queued behind it")
    func drain_replayBeginningTransaction_reDefersRemainder() {
        // The crash shape: a held transcript push replays and starts a new batch; a held inset
        // write queued behind it must wait for that batch too — never run inside it.
        let fence = ChatAnimationFence()
        fence.begin()
        var insetApplied = false
        fence.whenIdle { fence.begin() }        // the replayed push opens its own transaction
        fence.whenIdle { insetApplied = true }  // the inset write queued behind it
        fence.end()
        #expect(!insetApplied, "the remainder must wait behind the replay's transaction")
        fence.end()
        #expect(insetApplied)
    }

    @Test("Work registered during a drain joins the queue instead of jumping it")
    func drain_nestedWhenIdle_runsAfterCurrentQueue() {
        let fence = ChatAnimationFence()
        fence.begin()
        var order: [Int] = []
        fence.whenIdle {
            order.append(1)
            fence.whenIdle { order.append(3) } // registered mid-drain
        }
        fence.whenIdle { order.append(2) }
        fence.end()
        #expect(order == [1, 2, 3])
    }
}
