//
//  Collection+ConcurrentForEach.swift
//  Flipcash
//

import Foundation

extension Collection where Element: Sendable {

    /// Runs `body` on every element, at most `limit` at a time, and returns once all have finished.
    func concurrentForEach(limit: Int = 4, _ body: @escaping @Sendable (Element) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var pending = makeIterator()
            var started = 0
            while started < limit, let element = pending.next() {
                group.addTask { await body(element) }
                started += 1
            }
            // Replace each finished task with the next element, so the work drains at a steady
            // width rather than in lock-stepped batches.
            while await group.next() != nil {
                if let element = pending.next() {
                    group.addTask { await body(element) }
                }
            }
        }
    }
}
