//
//  DepositOperation.swift
//  Flipcash
//

import Foundation

// MARK: - State

/// Transient state a deposit operation exposes for its host view to observe.
nonisolated enum DepositOperationState: Equatable, Sendable {
    case idle
    case awaitingExternal(DepositExternalPrompt)
    case working
}

/// Out-of-app step a deposit operation is waiting on.
nonisolated enum DepositExternalPrompt: Equatable, Sendable {
    case applePay
    case phantomConnect
    case phantomSign
}

// MARK: - Requirements

/// Precondition a deposit path requires before `start()` will succeed.
nonisolated enum DepositRequirement: Hashable, Sendable {
    case verifiedContact
}

// MARK: - Errors

/// Typed errors thrown from a deposit operation's `start()`.
nonisolated enum DepositError: Error, Equatable, Sendable {
    case userCancelled
    case requirementUnsatisfied(DepositRequirement)
    /// An external resource rejected the deposit in an expected, user-facing
    /// way, carrying the dialog strings to render. Never reported to Bugsnag.
    case externalRejected(title: String, subtitle: String)
    /// A defensive precondition fired or an external contract was violated.
    /// Reported to Bugsnag.
    case unexpectedFailure(reason: String)
    /// The on-chain submit of a deposit transaction failed. Always reported to
    /// Bugsnag, even for network blips — money is in flight.
    case chainSubmitFailed(String)
}
