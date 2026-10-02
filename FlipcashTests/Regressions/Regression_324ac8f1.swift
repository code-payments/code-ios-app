//
//  Regression_324ac8f1.swift
//  Flipcash
//
//  Symptom:  RUNNINGBOARD 0xdead10cc SIGKILL. A chat feed load started on
//            foreground; its fetch returned after the app backgrounded and
//            `replaceConversationFeed` opened a write transaction on the App
//            Group store with no background-task assertion. iOS suspended the
//            app mid-transaction. Same kill as ffe0f684, from a writer that
//            fix's poller drain does not cover.
//
//  Fix:      Every write goes through `Database.write`, which holds an
//            injected `StoreWriteGuard` for the life of the write; the app's
//            guard holds one background-task assertion while any write is in
//            flight and refuses writes once iOS expires it.
//

import Foundation
import Testing
import UIKit
@testable import FlipcashCore
import FlipcashStore
@testable import Flipcash

/// Records guard calls and SQL statements on one timeline.
nonisolated private final class Timeline: StoreWriteGuard, @unchecked Sendable {

    private let lock = NSLock()
    private var _events: [String] = []
    var refuses = false

    var events: [String] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    func record(_ event: String) {
        lock.lock(); defer { lock.unlock() }
        _events.append(event)
    }

    func begin() throws {
        if refuses {
            record("refuse")
            throw StoreWriteRefused()
        }
        record("begin")
    }

    func end() {
        record("end")
    }

    /// Guard depth must return to zero, or the assertion leaks.
    var isBalanced: Bool {
        let events = events
        return events.filter { $0 == "begin" }.count == events.filter { $0 == "end" }.count
    }
}

/// Hands out sequential task identifiers and records which are still open.
nonisolated private final class FakeBackgroundTasks: BackgroundTaskAsserting, @unchecked Sendable {

    private let lock = NSLock()
    private var next = 1
    private var _open: Set<Int> = []
    private var expirations: [@Sendable () -> Void] = []
    var grants = true

    var open: Set<Int> {
        lock.lock(); defer { lock.unlock() }
        return _open
    }

    var beginCount: Int {
        lock.lock(); defer { lock.unlock() }
        return next - 1
    }

    func begin(expiration: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier {
        lock.lock(); defer { lock.unlock() }
        guard grants else { return .invalid }
        let id = next
        next += 1
        _open.insert(id)
        expirations.append(expiration)
        return UIBackgroundTaskIdentifier(rawValue: id)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        lock.lock(); defer { lock.unlock() }
        _open.remove(identifier.rawValue)
    }

    func expireAll() {
        lock.lock()
        let pending = expirations
        expirations = []
        lock.unlock()
        pending.forEach { $0() }
    }
}

@Suite("Regression: 324ac8f1 – store writes hold the write guard for their whole transaction", .bug("324AC8F1-2CC3-4E45-BF5B-8B66DADF7C8E"))
struct Regression_324ac8f1 {

    private func feed() -> [Conversation] {
        let message = ConversationMessage(id: MessageID(value: 1), senderID: UUID(), content: .text("hi"),
            date: Date(timeIntervalSince1970: 0), unreadSeq: 1, eventSequence: 1, reactionState: nil)
        return [Conversation(id: ConversationID.test(1), members: [], lastMessage: message,
            lastActivity: Date(timeIntervalSince1970: 100))]
    }

    // MARK: - Database -

    @Test("the crashing feed replace begins the guard before its transaction and ends it after commit")
    func feedReplace_holdsGuardAcrossTransaction() throws {
        let timeline = Timeline()
        let (database, url) = try Database.makeTemp(writeGuard: timeline)
        defer { Database.removeTemp(at: url) }
        try database.write { $0.trace { timeline.record($0) } }

        try database.replaceConversationFeed(feed(), type: .contactDm)

        let events = timeline.events
        let begin = try #require(events.firstIndex(of: "begin"))
        let open = try #require(events.firstIndex { $0.hasPrefix("BEGIN") })
        let commit = try #require(events.lastIndex { $0.hasPrefix("COMMIT") })
        let end = try #require(events.lastIndex(of: "end"))

        // The load-bearing ordering: an assertion that ended before COMMIT is the crash.
        #expect(begin < open)
        #expect(commit < end)
        #expect(timeline.isBalanced)
    }

    @Test("a refused write runs no SQL")
    func refusedWrite_runsNothing() throws {
        let timeline = Timeline()
        let (database, url) = try Database.makeTemp(writeGuard: timeline)
        defer { Database.removeTemp(at: url) }
        try database.write { $0.trace { timeline.record($0) } }

        let setup = timeline.events.count
        timeline.refuses = true
        #expect(throws: StoreWriteRefused.self) {
            try database.replaceConversationFeed(feed(), type: .contactDm)
        }

        // No BEGIN, no statement of any kind: the refusal lands before the connection is touched.
        #expect(Array(timeline.events.dropFirst(setup)) == ["refuse"])
    }

    @Test("a refused write is dropped by error reporting, not reported as a bug")
    func refusal_isSuppressed() {
        let error: any Error = StoreWriteRefused()
        let level = (error as? ServerError)?.reportingLevel
        #expect(level == .suppressed)
        #expect(ErrorReporting.outcome(for: .suppressed, userFacing: false) == .drop)
    }

    @Test("a write whose body throws still ends the guard")
    func throwingBody_endsGuard() throws {
        struct Boom: Error {}
        let timeline = Timeline()
        let (database, url) = try Database.makeTemp(writeGuard: timeline)
        defer { Database.removeTemp(at: url) }

        #expect(throws: Boom.self) {
            try database.write { _ in throw Boom() }
        }
        #expect(timeline.isBalanced)
    }

    // MARK: - BackgroundStoreWriteGuard -

    @Test("nested writes share one assertion, released by the last one out")
    func nestedWrites_shareOneAssertion() throws {
        let tasks = FakeBackgroundTasks()
        let writeGuard = BackgroundStoreWriteGuard(assertions: tasks)

        try writeGuard.begin()
        try writeGuard.begin()
        #expect(tasks.beginCount == 1)

        writeGuard.end()
        #expect(tasks.open == [1])
        writeGuard.end()
        #expect(tasks.open.isEmpty)
    }

    @Test("with no background time left the write is refused")
    func noBackgroundTime_refuses() {
        let tasks = FakeBackgroundTasks()
        tasks.grants = false
        let writeGuard = BackgroundStoreWriteGuard(assertions: tasks)

        #expect(throws: StoreWriteRefused.self) { try writeGuard.begin() }
    }

    @Test("after expiry, writes are refused until those in flight finish")
    func expiry_refusesUntilDrained() throws {
        let tasks = FakeBackgroundTasks()
        let writeGuard = BackgroundStoreWriteGuard(assertions: tasks)

        try writeGuard.begin()
        tasks.expireAll()
        #expect(tasks.open.isEmpty)

        // A nested write inside the expired transaction is refused without waiting on main.
        #expect(throws: StoreWriteRefused.self) { try writeGuard.begin() }

        writeGuard.end()
        try writeGuard.begin()
        #expect(tasks.open == [2])
        writeGuard.end()
        #expect(tasks.open.isEmpty)
    }
}
