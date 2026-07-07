//
//  DepositOperation.swift
//  Flipcash
//

import Foundation

// MARK: - State

/// Transient state a deposit operation exposes for its host view to observe.
///
/// Trimmed relative to the buy/launch funding flow: an Add Money deposit has
/// no in-app education/confirm gates, so there is no `.awaitingUserAction`
/// (and thus no `PaymentOperation` coupling). The flow only surfaces
/// external-app steps (the Apple Pay sheet, Phantom connect/sign) and a
/// working spinner.
nonisolated enum DepositOperationState: Equatable, Sendable {
    case idle
    case awaitingExternal(DepositExternalPrompt)
    case working
}

/// Out-of-app step a deposit operation is waiting on — the user is in the
/// Apple Pay sheet, or in Phantom. Drives the host's overlay rendering.
nonisolated enum DepositExternalPrompt: Equatable, Sendable {
    case applePay
    case phantomConnect
    case phantomSign
}

// MARK: - Requirements

/// Precondition a deposit path requires before `start()` will succeed. Only
/// Coinbase declares one (`.verifiedContact`); Phantom handles its connect
/// step inline.
nonisolated enum DepositRequirement: Hashable, Sendable {
    case verifiedContact
}

// MARK: - Errors

/// Typed errors thrown from a deposit operation's `start()`. Callers map them
/// to dialogs; operations themselves never touch UI.
nonisolated enum DepositError: Error, Equatable, Sendable {
    case userCancelled
    case requirementUnsatisfied(DepositRequirement)
    /// An external resource (Coinbase, Phantom, the chain) rejected the
    /// deposit in an expected, user-facing way (card declined, region
    /// blocked, user rejected in wallet). Carries pre-built dialog strings so
    /// call sites can render directly. Not reported to Bugsnag — these happen
    /// by design.
    case externalRejected(title: String, subtitle: String)
    /// A defensive precondition fired or an external contract was violated
    /// (missing field a caller should have guarded, malformed response from
    /// Coinbase/Phantom). Renders the generic "Something Went Wrong" dialog and
    /// falls through to Bugsnag — if this fires it's a bug or an API contract
    /// change worth investigating.
    case unexpectedFailure(reason: String)
    /// The on-chain submit of a deposit transaction failed. Reported to Bugsnag
    /// at error severity even when the underlying cause is a network blip — at
    /// this point money is in flight and the user's funds may be in limbo, so
    /// every occurrence is worth investigating.
    case chainSubmitFailed(String)
}
