//
//  SessionProtocols.swift
//  Flipcash
//

import Foundation
import FlipcashCore

// MARK: - Account

/// Account identity used by funding and verification operations.
protocol AccountProviding: AnyObject {
    var owner: AccountCluster { get }
    var ownerKeyPair: KeyPair { get }
}

// MARK: - Profile

/// Read-only access to the signed-in user's profile.
protocol ProfileProviding: AnyObject {
    var profile: Profile? { get }
}

/// Read-only access to the signed-in user's server-issued flags.
protocol UserFlagsProviding: AnyObject {
    var userFlags: UserFlags? { get }
}

/// Mutating profile operations — refresh from the server, unlink on logout
/// / region-mismatch.
protocol ProfileManaging: AnyObject {
    func updateProfile() async throws
    func unlinkProfile() async throws
}

// MARK: - Mint metadata

/// On-demand mint metadata lookup used to attach a token's display info to
/// a swap (Phantom buy fetches this before forwarding the sign request).
protocol MintMetadataFetching: AnyObject {
    func fetchMintMetadata(mint: PublicKey) async throws -> StoredMintMetadata
}

// MARK: - Buy paths

/// Reserve-funded buys (existing currency or freshly launched).
protocol ReservesBuying: AnyObject {

    func buy(
        amount: ExchangedFiat,
        verifiedState: VerifiedState,
        of mint: PublicKey
    ) async throws -> SwapId

    func buyNewCurrency(
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        verifiedState: VerifiedState,
        mint: PublicKey,
        swapId: SwapId
    ) async throws -> SwapId
}

/// External-wallet-funded buys (Phantom or any future wallet that signs a
/// USDC→USDF transaction directly).
protocol ExternalFundingBuying: AnyObject {

    /// `swapId` matches the USDC→USDF swap id the external wallet embedded
    /// in its on-chain swap instruction — server-side correlation between
    /// the funding tx and the recorded buy intent depends on this being
    /// the same value the wallet signed.
    func buyWithExternalFunding(
        swapId: SwapId,
        amount: ExchangedFiat,
        of mint: PublicKey,
        transactionSignature: Signature
    ) async throws -> SwapId

    func buyNewCurrencyWithExternalFunding(
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        mint: PublicKey,
        transactionSignature: Signature
    ) async throws -> SwapId
}

/// Coinbase / Apple Pay onramp-funded buys. The order is created out-of-band
/// (see `OnrampOrdering`); these RPCs hand the order id to the server so it
/// records the swap before Apple Pay commits.
protocol OnrampBuying: AnyObject {

    func buyWithCoinbaseOnramp(
        amount: ExchangedFiat,
        of mint: PublicKey,
        orderId: String
    ) async throws -> SwapId

    func buyNewCurrencyWithCoinbaseOnramp(
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        mint: PublicKey,
        orderId: String
    ) async throws -> SwapId
}

// MARK: - Currency launch

/// Launch-preflight: registers a brand-new currency with the backend before
/// any swap is initiated. Returns the mint that the subsequent buy/funding
/// path targets.
protocol CurrencyLaunching: AnyObject {

    func launchCurrency(
        name: String,
        description: String,
        billColors: [String],
        icon: Data,
        nameAttestation: ModerationAttestation,
        descriptionAttestation: ModerationAttestation,
        iconAttestation: ModerationAttestation
    ) async throws -> PublicKey
}

// MARK: - Recipient resolution

/// Resolves a contact's E.164 phone to their on-chain payment-destination
/// owner. Throws `ErrorResolve.notFound` when the contact isn't on Flipcash.
protocol RecipientResolving: AnyObject {

    func resolveContact(e164: String) async throws -> PublicKey
}

// MARK: - Direct send

/// Direct on-chain payment to a resolved recipient owner.
protocol DirectSending: AnyObject {

    func send(
        amount: ExchangedFiat,
        verifiedState: VerifiedState,
        to destination: PublicKey,
        chat: ChatPaymentMetadata?
    ) async throws
}

// MARK: - Session conformance

extension Session: AccountProviding,
                    ProfileProviding,
                    UserFlagsProviding,
                    ProfileManaging,
                    MintMetadataFetching,
                    ReservesBuying,
                    ExternalFundingBuying,
                    OnrampBuying,
                    CurrencyLaunching,
                    RecipientResolving,
                    DirectSending {}
