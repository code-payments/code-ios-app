//
//  NotificationStatusViewModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("NotificationStatusViewModel")
struct NotificationStatusViewModelTests {

    @Test("Check again shows every row as Checking, registers again, then settles")
    func checkAgainRerunsEveryCheck() async {
        let settings = Gate<NotificationStatus.Snapshot>(.init(authorization: .authorized))
        let registration = Gate<NotificationStatus.Registration>(.finished(.ok))
        let model = NotificationStatusViewModel(
            pushController: .mock,
            readSettings: { await settings.next() },
            registrationCheck: { _ in await registration.next() },
            recheckPause: .zero
        )

        await model.runChecks()
        await until { !model.isRunning }
        #expect(registration.calls == 1)
        #expect(model.page?.foldedTitle == "4 checks passed")

        settings.holdsNext = true
        registration.holdsNext = true
        let run = Task { await model.checkAgain() }
        await until { settings.isHolding && registration.isHolding }

        #expect(registration.calls == 2)
        #expect(model.isRunning)
        #expect(model.page?.rows.map(\.check) == NotificationStatus.Check.allCases)
        #expect(model.page?.rows.allSatisfy { $0.status == .checking } == true)
        #expect(model.page?.summary.status == .checking)

        settings.release()
        registration.release()
        await run.value

        #expect(!model.isRunning)
        #expect(model.page?.rows.allSatisfy { $0.status == .pass } == true)
    }

    @Test("Check again does nothing while a run is in progress")
    func checkAgainWhileRunning() async {
        let registration = Gate<NotificationStatus.Registration>(.finished(.ok))
        registration.holdsNext = true
        let model = NotificationStatusViewModel(
            pushController: .mock,
            readSettings: { .init(authorization: .authorized) },
            registrationCheck: { _ in await registration.next() },
            recheckPause: .zero
        )

        await model.runChecks()
        await until { registration.isHolding }
        await model.checkAgain()

        #expect(registration.calls == 1)
        registration.release()
    }

    @Test("A return to the foreground re-reads the phone's settings without registering again")
    func foregroundRereadsSettingsOnly() async {
        var snapshot = NotificationStatus.Snapshot(authorization: .authorized)
        let registration = Gate<NotificationStatus.Registration>(.finished(.ok))
        let model = NotificationStatusViewModel(
            pushController: .mock,
            readSettings: { snapshot },
            registrationCheck: { _ in await registration.next() },
            recheckPause: .zero
        )

        await model.runChecks()
        await until { !model.isRunning }
        #expect(model.page?.foldedTitle == "4 checks passed")

        snapshot = .init(authorization: .authorized, alertStyle: .none)
        await model.rereadSettings()

        #expect(registration.calls == 1, "AddToken runs only on open and on Check Again")
        #expect(!model.isRunning)
        #expect(model.page?.rows.first { $0.check == .display }?.status == .warning)
        #expect(model.page?.rows.first { $0.check == .registration }?.status == .pass)
    }

    // MARK: - Support -

    /// Yields until `condition` holds, so the view model's unstructured registration task can run.
    private func until(_ condition: () -> Bool) async {
        while !condition() {
            await Task.yield()
        }
    }
}

/// Returns `value` on each call, or, once `holdsNext` is set, suspends the next call until `release()`.
@MainActor
private final class Gate<Value: Sendable> {

    var holdsNext = false
    private(set) var calls = 0
    private let value: Value
    private var pending: CheckedContinuation<Value, Never>?

    var isHolding: Bool { pending != nil }

    init(_ value: Value) {
        self.value = value
    }

    func next() async -> Value {
        calls += 1
        guard holdsNext else { return value }
        holdsNext = false
        return await withCheckedContinuation { pending = $0 }
    }

    func release() {
        pending?.resume(returning: value)
        pending = nil
    }
}
