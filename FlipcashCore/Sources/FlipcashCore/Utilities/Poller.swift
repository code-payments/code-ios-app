//
//  Poller.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

/// Repeating async poller that serializes actions — each invocation
/// completes before the next sleep begins.
public final class Poller: Sendable {

    private let task: Task<Void, Never>

    public init(seconds: TimeInterval, fireImmediately: Bool = false, action: @Sendable @escaping () async -> Void) {
        task = Task {
            if fireImmediately {
                await action()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await action()
            }
        }
    }

    /// Stops the poller from starting another action.
    ///
    /// An action already in flight runs to completion: `action` is not required to be
    /// cancellation-aware, and the ones we pass are not — `fetchTransactionLimits` bridges a
    /// completion handler through a bare continuation. Pair with ``waitUntilFinished()`` when the
    /// caller needs to know nothing is still running.
    public func cancel() {
        task.cancel()
    }

    /// Waits for an in-flight action to finish.
    ///
    /// Call after ``cancel()`` on the way to the background: a SQLite write still holding its lock
    /// when iOS suspends the process is a `0xdead10cc` kill, not a slow next launch.
    public func waitUntilFinished() async {
        await task.value
    }

    deinit {
        task.cancel()
    }
}
