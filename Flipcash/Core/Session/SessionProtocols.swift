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

    func buyWithExternalFunding(
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

// MARK: - Session conformance

extension Session: AccountProviding,
                    ProfileProviding,
                    ProfileManaging,
                    MintMetadataFetching,
                    ReservesBuying,
                    ExternalFundingBuying,
                    OnrampBuying,
                    CurrencyLaunching {}
