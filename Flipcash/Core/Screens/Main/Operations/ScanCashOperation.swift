//
//  ScanCashOperation.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashCore
import Combine

/// Handles the receiver side of a face-to-face bill scan.
///
/// ## Device A (Sender)
/// Displays a bill via `SendCashOperation`, which:
/// - Advertises the mint + verified exchange data on a rendezvous channel
/// - Listens for a grab request on the same channel
///
/// ## Device B (Receiver — this class)
/// 1. **Listen for mint** — Poll the rendezvous channel until the sender's
///    `requestToGiveBill` message arrives. Extract the mint address,
///    `VerifiedState` (exchange rate + reserve state proofs), and
///    `MintMetadata` (server-provided via `additionalContext`) from the message.
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
    
    private var messageStream: AnyCancellable? = nil
    
    // MARK: - Init -
    
    init(client: Client, flipClient: FlipClient, database: Database, owner: AccountCluster, payload: CashCode.Payload) {
        self.client     = client
        self.flipClient = flipClient
        self.database   = database
        self.owner      = owner
        self.payload    = payload
        trace(.open, components: "ScanCashOperation \(payload.rendezvous.publicKey.base58)")
    }

    deinit {
        trace(.close, components: "ScanCashOperation \(payload.rendezvous.publicKey.base58)")
        messageStream?.cancel()
        messageStream = nil
    }
    
    func start() async throws -> PaymentMetadata {
        let rendezvous = payload.rendezvous
        let owner = owner

        let (mint, verifiedState, mintMetadata) = try await listenForMint(
            rendezvous: rendezvous
        )

        let vmAuthority: PublicKey
        if let mintMetadata, let authority = mintMetadata.vmMetadata?.authority {
            vmAuthority = authority
        } else {
            vmAuthority = try await pullMintIfNeeded(for: mint)
        }

        let mintCurrencyCluster = AccountCluster(
            authority: owner.authority,
            mint: mint,
            timeAuthority: vmAuthority
        )
        
        // We need to ensure the accounts for this mint
        // are created. This call is a no-op is the
        // account already exists
        try await client.createAccounts(
            owner: owner.authority.keyPair,
            mint: mint,
            cluster: mintCurrencyCluster,
            kind: .primary,
            derivationIndex: 0
        )
        
        return try await completePayment(
            destination: mintCurrencyCluster.vaultPublicKey,
            rendezvous: rendezvous,
            verifiedState: verifiedState
        )
    }
    
    private func pullMintIfNeeded(for mint: PublicKey) async throws -> PublicKey {
        if let vmAuthority = try database.getVMAuthority(mint: mint) {
            return vmAuthority
        } else {
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
    }
    
    private func listenForMint(rendezvous: KeyPair) async throws -> (PublicKey, VerifiedState?, MintMetadata?) {
        let maxAttempts = 10

        for i in 0..<maxAttempts {
            if i > 0 {
                try await Task.delay(milliseconds: 300)
            }

            do {
                let messages = try await client.fetchMessages(rendezvous: rendezvous)
                let result = messages.compactMap { message -> (PublicKey, VerifiedState?, MintMetadata?)? in
                    if case .requestToGiveBill(let mint, _, _) = message.kind {
                        return (mint, message.giveVerifiedState, message.giveMintMetadata)
                    }
                    return nil
                }.first

                if let result {
                    return result
                }
            } catch {
                trace(.warning, components: "Failed to fetch messages (attempt \(i + 1)/\(maxAttempts)): \(error)")
                throw Error.connectionFailed
            }
        }

        throw Error.mintMessageNotFound
    }
    
    private func completePayment(destination: PublicKey, rendezvous: KeyPair, verifiedState: VerifiedState?) async throws -> PaymentMetadata {
        do {
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
            
        } catch Error.noOpenStreamForRendezvous {
            throw Error.noOpenStreamForRendezvous // Avoid capture

        } catch ClientError.pollLimitReached {
            throw ClientError.pollLimitReached // Avoid capture

        } catch ClientError.denied {
            throw ClientError.denied // Avoid capture

        } catch {
//            ErrorReporting.captureError(error)
            throw error
        }
    }
}

extension ScanCashOperation {
    enum Error: Swift.Error {
        case noOpenStreamForRendezvous
        case sendPaymentMetadataNotFound
        case failedToFetchMint
        case missingVMAuthority
        case mintMessageNotFound

        /// A network error prevented fetching messages from the
        /// rendezvous channel (e.g. no internet connection).
        case connectionFailed
    }
}
