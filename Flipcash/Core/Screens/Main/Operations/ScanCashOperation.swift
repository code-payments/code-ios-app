//
//  ScanCashOperation.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.scan-cash")

/// Handles the receiver side of a face-to-face bill scan.
///
/// ## Device A (Sender)
/// Displays a bill via `SendCashOperation`, which:
/// - Advertises the mint + verified exchange data on a rendezvous channel
/// - Listens for a grab request on the same channel
///
/// ## Device B (Receiver — this class)
/// 1. **Listen for mint** — Subscribe to the rendezvous stream and wait for
///    the sender's `requestToGiveBill` message. Extract the mint address,
///    `VerifiedState` (exchange rate + reserve state proofs), and
///    `MintMetadata` (server-provided via `additionalContext`) from the
///    message.
/// 2. **Resolve VM authority** — Use the mint metadata from the message
///    when available (zero network cost). Falls back to a database lookup
///    or `fetchMints()` call for older servers that don't populate
///    `additionalContext`.
/// 3. **Create accounts** — Ensure Device B has token accounts for the mint.
/// 4. **Grab** — Send a `requestToGrabBill` with Device B's destination
///    account, signed by the rendezvous key to prove legitimacy.
/// 5. **Poll for settlement** — Wait for the sender's `transfer` intent to
///    settle on-chain, then return the payment metadata.
///
/// Both `VerifiedState` and `MintMetadata` come from the **sender's message**
/// (step 1), not from local caches. This means the scan path works even
/// when Device B has never synced this currency.
@MainActor
class ScanCashOperation {

    private let client: Client
    private let flipClient: FlipClient
    private let database: Database
    private let owner: AccountCluster
    private let payload: CashCode.Payload

    private var runTask: Task<PaymentMetadata, Swift.Error>?

    // MARK: - Init -

    init(client: Client, flipClient: FlipClient, database: Database, owner: AccountCluster, payload: CashCode.Payload) {
        self.client     = client
        self.flipClient = flipClient
        self.database   = database
        self.owner      = owner
        self.payload    = payload
        logger.info("ScanCashOperation opened", metadata: ["rendezvous": "\(payload.rendezvous.publicKey.base58)"])
    }

    deinit {
        logger.info("ScanCashOperation closed", metadata: ["rendezvous": "\(payload.rendezvous.publicKey.base58)"])
        runTask?.cancel()
    }

    // MARK: - Lifecycle -

    func start() async throws -> PaymentMetadata {
        let task = Task { try await self.run() }
        runTask = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    // MARK: - Run -

    private func run() async throws -> PaymentMetadata {
        let rendezvous = payload.rendezvous
        let owner = owner

        logger.info("Polling for give request", metadata: ["rendezvous": "\(rendezvous.publicKey.base58)"])
        let giveRequest = try await client.awaitGiveRequest(rendezvous: rendezvous)

        logger.info("Received give request", metadata: [
            "rendezvous": "\(rendezvous.publicKey.base58)",
            "mint": "\(giveRequest.mint.base58)",
            "hasVerifiedState": "\(giveRequest.verifiedState != nil)",
            "hasMintMetadata": "\(giveRequest.mintMetadata != nil)",
        ])

        let vmAuthority: PublicKey
        if let mintMetadata = giveRequest.mintMetadata, let authority = mintMetadata.vmMetadata?.authority {
            // Persist the metadata so downstream operations (e.g.
            // SendCashOperation for the quick give-and-grab chain)
            // can look it up from the database immediately.
            try? database.insert(mints: [mintMetadata], date: .now)
            logger.debug("VM authority resolved from give-request metadata", metadata: ["mint": "\(giveRequest.mint.base58)"])
            vmAuthority = authority
        } else {
            vmAuthority = try await pullMintIfNeeded(for: giveRequest.mint)
        }

        let mintCurrencyCluster = AccountCluster(
            authority: owner.authority,
            mint: giveRequest.mint,
            timeAuthority: vmAuthority
        )

        // No-op when the account already exists.
        try await client.createAccounts(
            owner: owner.authority.keyPair,
            mint: giveRequest.mint,
            cluster: mintCurrencyCluster,
            kind: .primary,
            derivationIndex: 0
        )

        return try await completePayment(
            destination: mintCurrencyCluster.vaultPublicKey,
            rendezvous: rendezvous,
            verifiedState: giveRequest.verifiedState
        )
    }

    // MARK: - Helpers -

    private func pullMintIfNeeded(for mint: PublicKey) async throws -> PublicKey {
        if let vmAuthority = try database.getVMAuthority(mint: mint) {
            logger.debug("VM authority resolved from database", metadata: ["mint": "\(mint.base58)"])
            return vmAuthority
        }

        logger.info("Fetching mint metadata from server", metadata: ["mint": "\(mint.base58)"])
        let mints = try await client.fetchMints(mints: [mint])
        guard let mintMetadata = mints[mint] else {
            throw Error.failedToFetchMint
        }

        try database.insert(mints: [mintMetadata], date: .now)

        guard let authority = mintMetadata.vmMetadata?.authority else {
            throw Error.failedToFetchMint
        }

        return authority
    }

    private func completePayment(destination: PublicKey, rendezvous: KeyPair, verifiedState: VerifiedState?) async throws -> PaymentMetadata {
        let isStreamOpen = try await client.sendRequestToGrabBill(
            destination: destination,
            rendezvous: rendezvous
        )

        guard isStreamOpen else {
            throw Error.noOpenStreamForRendezvous
        }

        let metadata = try await client.pollIntentMetadata(
            owner: owner.authority.keyPair,
            intentID: rendezvous.publicKey
        )

        if case .sendPayment(let paymentMetadata) = metadata {
            return PaymentMetadata(
                exchangedFiat: paymentMetadata.exchangedFiat,
                verifiedState: verifiedState
            )
        }

        if case .receivePayment(let paymentMetadata) = metadata {
            return PaymentMetadata(
                exchangedFiat: paymentMetadata.exchangedFiat,
                verifiedState: verifiedState
            )
        }

        throw Error.sendPaymentMetadataNotFound
    }
}

extension ScanCashOperation {
    enum Error: Swift.Error {
        case noOpenStreamForRendezvous
        case sendPaymentMetadataNotFound
        case failedToFetchMint
    }
}
