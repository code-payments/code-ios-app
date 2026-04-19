//
//  OnrampCoordinator.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.onramp-coordinator")

@MainActor
@Observable
final class OnrampCoordinator {

    // MARK: - Published state -

    /// Apple Pay order — drives the invisible WebView overlay hosted at root.
    private(set) var coinbaseOrder: OnrampOrderResponse?

    /// Non-nil when a verification sub-flow needs to present at root.
    var verificationSheet: VerificationSheetContext?

    /// Non-nil once the post-onramp swap succeeds. Drives the calling
    /// screen's processing-screen cover.
    var completion: OnrampCompletion?

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let coinbaseApiKey: String?
    @ObservationIgnored private var coinbase: Coinbase!

    // MARK: - Init -

    init(session: Session, flipClient: FlipClient) {
        self.session = session
        self.flipClient = flipClient
        self.owner = session.ownerKeyPair
        self.coinbaseApiKey = try? InfoPlist.value(for: "coinbase").value(for: "apiKey").string()

        self.coinbase = Coinbase(configuration: .init(bearerTokenProvider: fetchCoinbaseJWT))
    }

    // MARK: - Coinbase JWT -

    private func fetchCoinbaseJWT(method: String, path: String) async throws -> String {
        guard let coinbaseApiKey else {
            throw OnrampError.missingCoinbaseApiKey
        }

        return try await flipClient.fetchCoinbaseOnrampJWT(
            apiKey: coinbaseApiKey,
            owner: owner,
            method: method,
            path: path
        )
    }

    // MARK: - Public API (fleshed out in later tasks) -

    func startBuy(
        amount: ExchangedFiat,
        mint: PublicKey,
        displayName: String,
        onCompleted: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) {
        logger.info("startBuy invoked (stub)", metadata: [
            "currency": "\(amount.converted.currencyCode)",
            "mint": "\(mint.base58)",
        ])
    }

    func startLaunch(
        amount: ExchangedFiat,
        displayName: String,
        onCompleted: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) {
        logger.info("startLaunch invoked (stub)", metadata: [
            "currency": "\(amount.converted.currencyCode)",
        ])
    }

    func cancel() {
        coinbaseOrder = nil
        verificationSheet = nil
    }
}

// MARK: - Supporting types -

struct VerificationSheetContext: Identifiable, Hashable {
    enum Entry { case info, phone, email }

    let id: UUID = UUID()
    let entry: Entry
    let reason: OnrampOperation.LogKindWrapper  // placeholder hashable wrapper
}

extension OnrampOperation {
    /// Hashable wrapper so `OnrampOperation` itself (which carries closures)
    /// doesn't need Hashable conformance.
    struct LogKindWrapper: Hashable {
        let value: String
    }
}
