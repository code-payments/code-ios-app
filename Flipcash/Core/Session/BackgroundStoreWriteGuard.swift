//
//  BackgroundStoreWriteGuard.swift
//  Flipcash
//

import UIKit
import FlipcashCore
import FlipcashStore

nonisolated private let logger = Logger(label: "flipcash.store-write-guard")

/// Holds one background-task assertion while any store write is in flight, so iOS cannot suspend
/// the app with a SQLite lock held on the App Group store (`0xdead10cc`).
///
/// Writes nest and overlap across threads; only the outermost one takes the assertion and the last
/// one out releases it. Once iOS expires the assertion, further writes are refused rather than run
/// unprotected.
nonisolated final class BackgroundStoreWriteGuard: StoreWriteGuard, @unchecked Sendable {

    private let assertions: any BackgroundTaskAsserting

    /// Guarded by `lock`. `depth` counts writes in flight; `expired` is set when iOS ends the
    /// assertion under them and cleared once they have all finished.
    private let lock = NSLock()
    private var taskID: UIBackgroundTaskIdentifier = .invalid
    private var depth = 0
    private var expired = false

    init(assertions: any BackgroundTaskAsserting = UIApplicationBackgroundTasks()) {
        self.assertions = assertions
    }

    func begin() throws {
        lock.lock()
        if expired && depth > 0 {
            lock.unlock()
            throw StoreWriteRefused()
        }
        if taskID != .invalid {
            depth += 1
            lock.unlock()
            return
        }
        lock.unlock()

        // Acquired outside `lock`: off the main thread this waits on main, and main may itself be
        // waiting on `lock` to begin a write. Nested begins never get here — while a write is in
        // flight `taskID` is valid or `expired` is set — so a thread already inside a transaction
        // never waits on main.
        let acquired = assertions.begin { [weak self] in self?.expire() }
        guard acquired != .invalid else {
            logger.info("Store write refused, no background time left")
            throw StoreWriteRefused()
        }

        lock.lock()
        var surplus = UIBackgroundTaskIdentifier.invalid
        if taskID == .invalid {
            taskID = acquired
            expired = false
        } else {
            // Another thread acquired one while this one waited on main.
            surplus = acquired
        }
        depth += 1
        lock.unlock()

        if surplus != .invalid {
            assertions.end(surplus)
        }
    }

    func end() {
        lock.lock()
        depth -= 1
        var released = UIBackgroundTaskIdentifier.invalid
        if depth == 0 {
            released = taskID
            taskID = .invalid
            expired = false
        }
        lock.unlock()

        if released != .invalid {
            assertions.end(released)
        }
    }

    /// iOS is out of patience. A write still running cannot be interrupted from here; ending the
    /// assertion is required regardless, or the expiry itself is a kill.
    private func expire() {
        lock.lock()
        let expiring = taskID
        taskID = .invalid
        expired = true
        let inFlight = depth
        lock.unlock()

        logger.warning("Store write assertion expired", metadata: ["writesInFlight": "\(inFlight)"])
        if expiring != .invalid {
            assertions.end(expiring)
        }
    }
}

/// The two `UIApplication` background-task calls, behind a seam so the guard's bookkeeping can be
/// tested without a running app.
nonisolated protocol BackgroundTaskAsserting: Sendable {

    /// Begins a background task from any thread; `.invalid` when iOS grants no more time.
    func begin(expiration: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier

    /// Ends a task from any thread without waiting.
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

/// ``BackgroundTaskAsserting`` over `UIApplication.shared`, hopping to the main thread it requires.
nonisolated struct UIApplicationBackgroundTasks: BackgroundTaskAsserting {

    /// The name iOS reports the task under in its diagnostics.
    var name = "database.write"

    func begin(expiration: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier {
        let begin = {
            MainActor.assumeIsolated {
                UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expiration)
            }
        }
        return Thread.isMainThread ? begin() : DispatchQueue.main.sync(execute: begin)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { UIApplication.shared.endBackgroundTask(identifier) }
        } else {
            DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(identifier) }
        }
    }
}

/// One background-task assertion, held from ``begin()`` until ``end()`` or until iOS expires it.
nonisolated final class BackgroundTimeAssertion: @unchecked Sendable {

    private let assertions: any BackgroundTaskAsserting

    /// Guarded by `lock`.
    private let lock = NSLock()
    private var taskID: UIBackgroundTaskIdentifier = .invalid

    init(assertions: any BackgroundTaskAsserting) {
        self.assertions = assertions
    }

    /// Asks iOS to keep the app running after it leaves the screen; a no-op when none is granted.
    func begin() {
        // Expiry only ends the assertion: the work under it carries on until iOS suspends the app.
        let acquired = assertions.begin { [weak self] in self?.end() }
        lock.withLock { taskID = acquired }
    }

    /// Releases the assertion; safe to call more than once.
    func end() {
        let held = lock.withLock {
            defer { taskID = .invalid }
            return taskID
        }
        if held != .invalid {
            assertions.end(held)
        }
    }
}
