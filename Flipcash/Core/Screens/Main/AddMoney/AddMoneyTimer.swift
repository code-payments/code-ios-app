//
//  AddMoneyTimer.swift
//  Flipcash
//

import Foundation
import os

/// Times the phases of a Coinbase add-money purchase for the `Add Money` event.
/// `start()` opens a purchase, each `Moment` is marked once as it happens, and
/// `finish()` reads the phases and closes the purchase.
///
/// Marks arrive from the main actor and from the USDC sweep actors, so state sits
/// behind a lock. The clock is monotonic; tests pass their own.
nonisolated final class AddMoneyTimer: Sendable {

    /// The moments a purchase passes through, in order.
    enum Moment: Int, Comparable, Sendable {
        /// Coinbase returned the placed order.
        case orderPlaced
        /// Coinbase's `onramp_api.payment_authorized` webview event.
        case paymentAuthorized
        /// Coinbase's `onramp_api.polling_success` webview event.
        case paymentCompleted
        /// A USDC sweep first saw a nonzero USDC balance.
        case usdcSeen
        /// The USDC to USDF swap returned success.
        case swapped
        /// The USDF credit landed and the success state was shown.
        case credited

        static func < (lhs: Moment, rhs: Moment) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct State {
        var started: ContinuousClock.Instant?
        var marks: [Moment: ContinuousClock.Instant] = [:]
    }

    private let now: @Sendable () -> ContinuousClock.Instant
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.now = now
    }

    /// Opens a purchase, dropping any marks from an earlier one.
    func start() {
        let instant = now()
        state.withLock {
            $0.marks.removeAll()
            $0.started = instant
        }
    }

    /// Records `moment` the first time it happens in an open purchase. The USDC
    /// sweeps also run for leftover balances, so their moments only count once
    /// Coinbase has completed the payment.
    func mark(_ moment: Moment) {
        let instant = now()
        state.withLock {
            guard $0.started != nil else { return }
            if moment >= .usdcSeen, $0.marks[.paymentCompleted] == nil { return }
            if $0.marks[moment] == nil { $0.marks[moment] = instant }
        }
    }

    /// The phases so far and the total up to now, or nil when no purchase is open.
    /// Closes the purchase so a later send can't reuse its marks.
    func finish() -> AddMoneyPhases? {
        let instant = now()
        return state.withLock { state in
            guard let started = state.started else { return nil }
            let marks = state.marks
            let phases = AddMoneyPhases(
                order: Self.millis(from: started, to: marks[.orderPlaced]),
                payment: Self.millis(from: marks[.orderPlaced], to: marks[.paymentAuthorized]),
                coinbase: Self.millis(from: marks[.paymentAuthorized], to: marks[.paymentCompleted]),
                deposit: Self.millis(from: marks[.paymentCompleted], to: marks[.usdcSeen]),
                swap: Self.millis(from: marks[.usdcSeen], to: marks[.swapped]),
                credit: Self.millis(from: marks[.swapped], to: marks[.credited]),
                total: Self.millis(from: started, to: instant) ?? 0
            )
            state = State()
            return phases
        }
    }

    /// The phases for a send by `method`: only Coinbase carries them.
    func finish(for method: DepositMethod) -> AddMoneyPhases? {
        switch method {
        case .coinbase:                 finish()
        case .phantom, .otherWallet:    nil
        }
    }

    private static func millis(from: ContinuousClock.Instant?, to: ContinuousClock.Instant?) -> Int64? {
        guard let from, let to else { return nil }
        let parts = (to - from).components
        return parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000
    }
}

/// Milliseconds per `Add Money` phase. A phase is nil when either of its moments never happened.
nonisolated struct AddMoneyPhases: Equatable, Sendable {
    let order: Int64?
    let payment: Int64?
    let coinbase: Int64?
    let deposit: Int64?
    let swap: Int64?
    let credit: Int64?
    let total: Int64
}
