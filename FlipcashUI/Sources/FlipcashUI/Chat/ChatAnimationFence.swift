//
//  ChatAnimationFence.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import Foundation
import FlipcashCore

/// Serializes the transcript's animated layout work: transactions bracket `begin()`/`end()`,
/// queued work replays in order once the last one settles, and the latest push and bar inset
/// wait in the held slots.
///
/// ChatLayout answers attribute queries with nil during `restoreContentOffset`, so a restore or
/// inset write overlapping an animated transaction throws UIKit's "missing final attributes for
/// cell" — the collision this type exists to prevent (see the chat pitfall row in CLAUDE.md).
@MainActor
final class ChatAnimationFence {

    /// The latest transcript push held while a transaction or context menu blocks applying it.
    var heldItems: (items: [ChatItem], animated: Bool)?
    /// The latest bar inset held while a transaction blocks applying it.
    var heldBottomInset: CGFloat?

    private(set) var activeCount = 0
    private var idleWork: [() -> Void] = []
    private var isDraining = false

    var isActive: Bool { activeCount > 0 }

    /// Marks an animated transaction as started.
    func begin() {
        activeCount += 1
    }

    /// Marks a transaction as settled, replaying queued work once none remain.
    func end() {
        assert(activeCount > 0, "Unbalanced ChatAnimationFence.end()")
        activeCount = max(0, activeCount - 1)
        drainIfIdle()
    }

    /// Runs `work` now if nothing is animating, otherwise once the last transaction settles.
    func whenIdle(_ work: @escaping () -> Void) {
        idleWork.append(work)
        drainIfIdle()
    }

    private func drainIfIdle() {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        // Re-checked before every item: a replayed closure may begin a new transaction that the
        // remainder must wait behind.
        while activeCount == 0, !idleWork.isEmpty {
            idleWork.removeFirst()()
        }
    }
}
#endif
