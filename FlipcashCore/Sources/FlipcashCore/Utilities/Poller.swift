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
///
/// The internal `Task` inherits the caller's actor isolation.
/// Both current callers are `@MainActor` (Session, SessionAuthenticator),
/// matching the old `RunLoop.main` behavior.
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

    deinit {
        task.cancel()
    }
}
