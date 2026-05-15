//
//  MockSession.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore

/// Closure-driven mock that conforms to every Session-side protocol an
/// operation might depend on. Each method is backed by an optional handler
/// — tests assign handlers for the methods they exercise and leave the rest
/// nil. Handlers default to throwing `MockSessionError.unimplemented` so a
/// test never accidentally observes a "success" from an unset stub.
@MainActor
final class MockSession:
    AccountProviding,
    ProfileProviding,
    ProfileManaging,
    MintMetadataFetching,
    ReservesBuying,
    ExternalFundingBuying,
    OnrampBuying,
    CurrencyLaunching {

    // MARK: - Identity

    var profile: Profile?
    let owner: AccountCluster
    let ownerKeyPair: KeyPair

    init(profile: Profile? = nil) {
        let sample = Session.mock
        self.owner = sample.owner
        self.ownerKeyPair = sample.ownerKeyPair
        self.profile = profile
    }

    // MARK: - Profile

    var updateProfileHandler: (@MainActor () async throws -> Void)?
    var unlinkProfileHandler: (@MainActor () async throws -> Void)?

    func updateProfile() async throws {
        try await updateProfileHandler?()
    }

    func unlinkProfile() async throws {
        try await unlinkProfileHandler?()
    }

    // MARK: - Mint metadata

    var fetchMintMetadataHandler: (@MainActor (PublicKey) async throws -> StoredMintMetadata)?

    func fetchMintMetadata(mint: PublicKey) async throws -> StoredMintMetadata {
        guard let handler = fetchMintMetadataHandler else {
            throw MockSessionError.unimplemented(method: "fetchMintMetadata")
        }
        return try await handler(mint)
    }

    // MARK: - Reserves

    var buyHandler: (@MainActor (ExchangedFiat, VerifiedState, PublicKey) async throws -> SwapId)?
    var buyNewCurrencyHandler: (@MainActor (ExchangedFiat, ExchangedFiat, VerifiedState, PublicKey, SwapId) async throws -> SwapId)?

    private(set) var buyCalls: [(amount: ExchangedFiat, verifiedState: VerifiedState, mint: PublicKey)] = []
    private(set) var buyNewCurrencyCalls: [(amount: ExchangedFiat, feeAmount: ExchangedFiat, verifiedState: VerifiedState, mint: PublicKey, swapId: SwapId)] = []

    func buy(amount: ExchangedFiat, verifiedState: VerifiedState, of mint: PublicKey) async throws -> SwapId {
        buyCalls.append((amount, verifiedState, mint))
        guard let handler = buyHandler else {
            throw MockSessionError.unimplemented(method: "buy")
        }
        return try await handler(amount, verifiedState, mint)
    }

    func buyNewCurrency(
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        verifiedState: VerifiedState,
        mint: PublicKey,
        swapId: SwapId
    ) async throws -> SwapId {
        buyNewCurrencyCalls.append((amount, feeAmount, verifiedState, mint, swapId))
        guard let handler = buyNewCurrencyHandler else {
            throw MockSessionError.unimplemented(method: "buyNewCurrency")
        }
        return try await handler(amount, feeAmount, verifiedState, mint, swapId)
    }

    // MARK: - External funding

    var buyWithExternalFundingHandler: (@MainActor (ExchangedFiat, PublicKey, Signature) async throws -> SwapId)?
    var buyNewCurrencyWithExternalFundingHandler: (@MainActor (ExchangedFiat, ExchangedFiat, PublicKey, Signature) async throws -> SwapId)?

    func buyWithExternalFunding(amount: ExchangedFiat, of mint: PublicKey, transactionSignature: Signature) async throws -> SwapId {
        guard let handler = buyWithExternalFundingHandler else {
            throw MockSessionError.unimplemented(method: "buyWithExternalFunding")
        }
        return try await handler(amount, mint, transactionSignature)
    }

    func buyNewCurrencyWithExternalFunding(
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        mint: PublicKey,
        transactionSignature: Signature
    ) async throws -> SwapId {
        guard let handler = buyNewCurrencyWithExternalFundingHandler else {
            throw MockSessionError.unimplemented(method: "buyNewCurrencyWithExternalFunding")
        }
        return try await handler(amount, feeAmount, mint, transactionSignature)
    }

    // MARK: - Onramp

    var buyWithCoinbaseOnrampHandler: (@MainActor (ExchangedFiat, PublicKey, String) async throws -> SwapId)?
    var buyNewCurrencyWithCoinbaseOnrampHandler: (@MainActor (ExchangedFiat, ExchangedFiat, PublicKey, String) async throws -> SwapId)?

    func buyWithCoinbaseOnramp(amount: ExchangedFiat, of mint: PublicKey, orderId: String) async throws -> SwapId {
        guard let handler = buyWithCoinbaseOnrampHandler else {
            throw MockSessionError.unimplemented(method: "buyWithCoinbaseOnramp")
        }
        return try await handler(amount, mint, orderId)
    }

    func buyNewCurrencyWithCoinbaseOnramp(
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        mint: PublicKey,
        orderId: String
    ) async throws -> SwapId {
        guard let handler = buyNewCurrencyWithCoinbaseOnrampHandler else {
            throw MockSessionError.unimplemented(method: "buyNewCurrencyWithCoinbaseOnramp")
        }
        return try await handler(amount, feeAmount, mint, orderId)
    }

    // MARK: - Launch

    struct LaunchCall: Sendable {
        let name: String
        let description: String
        let billColors: [String]
        let icon: Data
        let nameAttestation: ModerationAttestation
        let descriptionAttestation: ModerationAttestation
        let iconAttestation: ModerationAttestation
    }

    var launchCurrencyHandler: (@MainActor (LaunchCall) async throws -> PublicKey)?
    private(set) var launchCurrencyCalls: [LaunchCall] = []

    func launchCurrency(
        name: String,
        description: String,
        billColors: [String],
        icon: Data,
        nameAttestation: ModerationAttestation,
        descriptionAttestation: ModerationAttestation,
        iconAttestation: ModerationAttestation
    ) async throws -> PublicKey {
        let call = LaunchCall(
            name: name,
            description: description,
            billColors: billColors,
            icon: icon,
            nameAttestation: nameAttestation,
            descriptionAttestation: descriptionAttestation,
            iconAttestation: iconAttestation
        )
        launchCurrencyCalls.append(call)
        guard let handler = launchCurrencyHandler else {
            throw MockSessionError.unimplemented(method: "launchCurrency")
        }
        return try await handler(call)
    }
}

enum MockSessionError: Error, Equatable {
    case unimplemented(method: String)
}
