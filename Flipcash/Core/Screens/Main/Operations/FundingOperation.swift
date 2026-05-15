//
//  FundingOperation.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

// MARK: - StartedSwap

/// Result of a successfully started funding flow. Every `FundingOperation`
/// returns this when the chain has accepted the transaction —
/// `SwapProcessingScreen` consumes it identically regardless of which path
/// produced the swap.
nonisolated struct StartedSwap: Hashable, Sendable {

    let swapId: SwapId
    let swapType: SwapType
    let currencyName: String
    let amount: ExchangedFiat
    /// Non-nil only for launch-flavoured `swapType` values. Lets the
    /// processing screen surface the newly-launched mint once settlement
    /// completes.
    let launchedMint: PublicKey?
}

// MARK: - State

/// Per-operation transient state. Views observe this to push the right
/// prompt screen (`.awaitingUserAction`), render an external-app overlay
/// (`.awaitingExternal`), or surface a recoverable error (`.failed`).
nonisolated enum FundingOperationState: Equatable, Sendable {
    case idle
    case awaitingUserAction(UserPrompt)
    case awaitingExternal(ExternalPrompt)
    case working
    case failed(reason: String)
}

/// In-app prompt the operation is waiting on. The host view pushes the
/// matching destination; the prompt screen's CTA calls `confirm()`.
nonisolated enum UserPrompt: Equatable, Sendable {
    case education(PaymentOperation)
    case confirm(PaymentOperation)
}

/// Out-of-app prompt — the user is in Phantom, in the Apple Pay sheet, etc.
/// Drives the host's overlay rendering, no navigation push.
nonisolated enum ExternalPrompt: Equatable, Sendable {
    case phantom
    case applePay
}

// MARK: - Prompt routing

/// Pure mapping target for `FundingFlowHost`. Lifted out of the host so it
/// can be unit-tested without SwiftUI. `nil` means "leave the stack alone".
///
/// Cases are payload-free; the host modifier discriminates which kind of
/// prompt to push and supplies the operation reference separately when
/// constructing the `AppRouter.Destination` case.
nonisolated enum FundingPromptDestination: Hashable, Sendable {
    case phantomEducation
    case phantomConfirm
}

// MARK: - Requirements

/// Precondition the caller has to satisfy before `start()` will succeed.
/// Today only Coinbase declares one (`.verifiedContact`); Phantom handles
/// its connect step inline.
nonisolated enum FundingRequirement: Hashable, Sendable {
    case verifiedContact
}

// MARK: - Errors

/// Typed errors thrown from `start()`. Callers map them to dialogs;
/// operations themselves never touch UI.
nonisolated enum FundingOperationError: Error, Equatable, Sendable {
    case userCancelled
    case requirementUnsatisfied(FundingRequirement)
    case insufficientBalance
    case serverRejected(String)
    case chainSubmitFailed(String)
}

// MARK: - Protocol

/// Strict contract every funding path implements (reserves, Phantom,
/// Coinbase, plus future paths). Mirrors `SendCashOperation` in shape: a
/// plain class with `init(deps)`, imperative `start()` returning the
/// `StartedSwap` on chain-submission success, and `cancel()` for teardown.
///
/// Multi-step paths interleave navigation without inverting control —
/// the operation transitions `state` to `.awaitingUserAction(...)`, the
/// host view pushes the matching prompt screen, the prompt's CTA calls
/// `confirm()`, and `start()` resumes from the suspended continuation.
protocol FundingOperation: AnyObject, Observable {

    /// Transient state the host view observes to push prompts / render
    /// overlays.
    var state: FundingOperationState { get }

    /// Preconditions the caller must satisfy before `start()`. Each
    /// requirement is satisfied by its own dedicated operation (e.g.
    /// `VerificationOperation` for `.verifiedContact`).
    var requirements: [FundingRequirement] { get }

    /// Imperative entry point. Returns once the chain has accepted the
    /// transaction (server is recording; `SwapProcessingScreen` will poll
    /// settlement). Throws on user cancel, server reject, chain submit
    /// error, or any unsatisfied precondition.
    func start(_ operation: PaymentOperation) async throws -> StartedSwap

    /// Resumes the operation when `state == .awaitingUserAction`. No-op
    /// otherwise.
    func confirm()

    /// Cancels an in-flight start. Idempotent. The pending `start()`
    /// throws `CancellationError`.
    func cancel()
}
